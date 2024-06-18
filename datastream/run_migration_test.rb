# frozen_string_literal: true
require 'securerandom'

# Use your own Flink home path instead
FLINK_HOME = ENV['FLINK_HOME']
throw 'Unspecified `FLINK_HOME` environment variable.' if FLINK_HOME.nil?

SOURCE_PORT = 3306
DATABASE_NAME = 'fallen'

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
  # Clear previous savepoints and logs
  `rm -rf savepoints`

  old_job_id = `#{FLINK_HOME}/bin/flink run -p 1 -c DataStreamJob --detached datastream-#{from_version}/target/datastream-job-#{from_version}-jar-with-dependencies.jar`.split.last
  raise StandardError.new("Failed to submit Flink job") unless old_job_id.length == 32
  puts "Submitted job at #{from_version} as #{old_job_id}"

  random_string_1 = SecureRandom.hex(8)
  put_mystery_data random_string_1
  sleep 5
  ensure_mystery_data random_string_1

  puts `#{FLINK_HOME}/bin/flink stop --savepointPath #{Dir.pwd}/savepoints #{old_job_id}`
  savepoint_file = `ls savepoints`.split("\n").last
  new_job_id = `#{FLINK_HOME}/bin/flink run --fromSavepoint #{Dir.pwd}/savepoints/#{savepoint_file} -p 1 -c DataStreamJob --detached datastream-#{to_version}/target/datastream-job-#{to_version}-jar-with-dependencies.jar`.split.last
  raise StandardError.new("Failed to submit Flink job") unless new_job_id.length == 32

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
  rescue StandardError
    puts "❌ [MIGRATION] Failed to migrate from #{from_version} to #{to_version}..."
    false
  end
end

version_list = %w[2.4.2 3.0.0 3.0.1 3.1.0 3.1-SNAPSHOT 3.2-SNAPSHOT]
version_result = Hash.new('❓')

version_list.each_with_index do |old_version, old_index|
  puts 'Restarting cluster...'
  `#{FLINK_HOME}/bin/stop-cluster.sh`
  `rm -rf #{FLINK_HOME}/log/flink-*.out`
  `#{FLINK_HOME}/bin/start-cluster.sh`
  version_list.each_with_index do |new_version, new_index|
    next if old_index > new_index

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
