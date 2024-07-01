# frozen_string_literal: true

require 'securerandom'

FLINK_HOME = ENV['FLINK_HOME']
throw 'Unspecified `FLINK_HOME` environment variable.' if FLINK_HOME.nil?

SOURCE_PORT = 3306
DATABASE_NAME = 'fallen'
TABLES = ['girl']

def exec_sql_source(sql)
  `mysql -h 127.0.0.1 -P#{SOURCE_PORT} -uroot --skip-password -e "USE #{DATABASE_NAME}; #{sql}" 2>/dev/null`
end

def put_mystery_data(mystery)
  exec_sql_source("REPLACE INTO girl(id, name) VALUES (17, '#{mystery}');")
end

def ensure_mystery_data(mystery)
  throw "Failed to get specific mystery string" unless `cat #{FLINK_HOME}/log/*.out`.include? mystery
end


def test_migration_chore(from_version, to_version)
  TABLES.each do |table_name|
    exec_sql_source("DROP TABLE IF EXISTS #{table_name};")
    exec_sql_source("CREATE TABLE #{table_name} (ID INT NOT NULL, NAME VARCHAR(17), PRIMARY KEY (ID));")
  end

  # Clear previous savepoints and logs
  `rm -rf savepoints`

  # Prepare for current YAML file
  test_route = !%w[3.0.0 3.0.1].include?(from_version)
  yaml_job_file = test_route ? 'conf/pipeline-route.yaml' : 'conf/pipeline.yaml'

  # Submit current pipeline job file
  submit_job_output = `bash ./cdc-versions/#{from_version}/bin/flink-cdc.sh --flink-home #{FLINK_HOME} #{yaml_job_file}`
  puts "   #{submit_job_output}"
  current_job_id = submit_job_output.split("\n")[1].split.last
  raise StandardError.new("Failed to submit Flink job") unless current_job_id.length == 32
  puts "   Current Job ID: #{current_job_id}"

  # Verify if data sync works
  random_string_1 = SecureRandom.hex(8)
  put_mystery_data random_string_1
  sleep 5
  ensure_mystery_data random_string_1

  # Stop current job and create a savepoint
  puts `#{FLINK_HOME}/bin/flink stop --savepointPath #{Dir.pwd}/savepoints #{current_job_id}`
  savepoint_file = `ls savepoints`.split("\n").last

  # Migrate to a newer CDC version
  puts "   Submitting CDC jobs at #{to_version}..."
  submit_job_output = `bash ./cdc-versions/#{to_version}/bin/flink-cdc.sh --from-savepoint #{Dir.pwd}/savepoints/#{savepoint_file} --allow-nonRestored-state --flink-home #{FLINK_HOME} #{yaml_job_file}`
  puts "   #{submit_job_output}"
  new_job_id = submit_job_output.split("\n")[1].split.last
  raise StandardError.new("Failed to submit Flink job") unless new_job_id.length == 32
  puts "   Upgraded Job ID: #{new_job_id}"

  # Verify if data sync works
  puts "Submitted job at #{to_version} as #{new_job_id}"
  random_string_2 = SecureRandom.hex(8)
  put_mystery_data random_string_2
  sleep 10
  ensure_mystery_data random_string_2
  puts `#{FLINK_HOME}/bin/flink cancel #{new_job_id}`
  true
end

def test_migration(from_version, to_version)
  puts "➡️ [MIGRATION] Testing migration from #{from_version} to #{to_version}..."
  puts "   with Flink #{FLINK_HOME}..."
  begin
    result = test_migration_chore from_version, to_version
    if result
      puts "✅ [MIGRATION] Successfully migrated from #{from_version} to #{to_version}!"
    else
      puts "❌ [MIGRATION] Failed to migrate from #{from_version} to #{to_version}..."
    end
    result
  rescue NoMethodError
    puts "❌ [MIGRATION] Failed to migrate from #{from_version} to #{to_version}..."
    false
  end
end

version_list = %w[3.0.0 3.0.1 3.1.0 3.1.1 3.2-SNAPSHOT]
no_savepoint_versions = %w[3.0.0 3.0.1]
version_result = Hash.new('❓')

version_list.each_with_index do |old_version, old_index|
  puts 'Restarting cluster...'
  `#{FLINK_HOME}/bin/stop-cluster.sh`
  puts 'Stopped cluster.'
  `#{FLINK_HOME}/bin/start-cluster.sh`
  puts 'Started cluster.'
  version_list.each_with_index do |new_version, new_index|
    next if old_index > new_index
    next if no_savepoint_versions.include? new_version

    result = test_migration old_version, new_version
    version_result[old_version + new_version] = result ? '✅' : '❌'
  end
end

printable_result = []
printable_result << [''] + version_list
version_list.each_with_index do |old_version, old_index|
  table_line = [old_version]
  version_list.each_with_index do |new_version, new_index|
    table_line << if old_index > new_index
                    ''
                  else
                    version_result[old_version + new_version]
                  end
  end
  printable_result << table_line
end

begin
  require 'terminal-table'
  puts Terminal::Table.new rows: printable_result, title: 'Migration Test Result'
rescue LoadError
  puts 'Test summary: ', printable_result
end
