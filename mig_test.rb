# frozen_string_literal: true
require 'terminal-table'

# Use your own Flink home path instead
FLINK_HOME = '~/Documents/Flink/flink-1.18.1'
SOURCE_PORT = 3306
SINK_HTTP_PORT = 8080
SINK_SQL_PORT = 9030
DATABASE_NAME = 'fallen'
TABLES = %w[angel gabriel girl].freeze

YAML_JOB_FILE = 'conf/pipeline.yaml'
SIMULATE_SIZE = 10_240
MAX_RETRY = 170

puts 'Restarting cluster...'
`#{FLINK_HOME}/bin/stop-cluster.sh`
`#{FLINK_HOME}/bin/start-cluster.sh`

puts 'Preparing test data...'

File.open('_phase_1.sql', 'w') do |f|
  1.upto(SIMULATE_SIZE).each do |num|
    f.write("INSERT INTO #{TABLES.sample(1)[0]} VALUES (#{num}, 'num_#{num}');\n")
  end
end

File.open('_phase_2.sql', 'w') do |f|
  SIMULATE_SIZE.upto(SIMULATE_SIZE * 2).each do |num|
    f.write("INSERT INTO #{TABLES.sample(1)[0]} VALUES (#{num}, 'num_#{num}');\n")
  end
end

def exec_sql_source(sql)
  `mysql -h 127.0.0.1 -P#{SOURCE_PORT} -uroot --skip-password -e "USE #{DATABASE_NAME}; #{sql}" 2>/dev/null`
end

def exec_sql_sink(sql)
  `mysql -h 127.0.0.1 -P#{SINK_SQL_PORT} -uroot --skip-password -e "#{sql}" 2>/dev/null`
end

def test_migration_chore(from_version, to_version)
  puts '   Cleaning up stale jobs...'
  `#{FLINK_HOME}/bin/flink list`.split("\n").each do |line|
    job_id = line.split(' : ')[1]
    `#{FLINK_HOME}/bin/flink cancel #{job_id}` unless job_id.nil?
    puts "Killed job #{line}" unless job_id.nil?
  end

  `rm -rf savepoints`
  puts '   Waiting for source to start up...'
  next until exec_sql_source("SELECT '1';") == "1\n1\n"

  puts '   Waiting for sink to start up...'
  next until exec_sql_sink("SELECT '1';") == "'1'\n1\n"

  puts '   Initializing source tables...'
  exec_sql_sink("DROP DATABASE IF EXISTS #{DATABASE_NAME};")

  TABLES.each do |table_name|
    exec_sql_source("DROP TABLE IF EXISTS #{table_name};")
    exec_sql_source("CREATE TABLE #{table_name} (ID INT NOT NULL, NAME VARCHAR(17), PRIMARY KEY (ID));")
  end
  exec_sql_source("source #{Dir.pwd}/_phase_1.sql")

  puts "   Submitting CDC jobs at #{from_version}..."
  submit_job_output = `bash ./cdc-versions/#{from_version}/bin/flink-cdc.sh --flink-home #{FLINK_HOME} #{YAML_JOB_FILE}`
  puts "   #{submit_job_output}"
  current_job_id = submit_job_output.split("\n")[1].split.last
  puts "   Current Job ID: #{current_job_id}"

  puts '   Checking Phase 1 sync progress...'
  wait_times = 0
  loop do
    count = exec_sql_sink("USE #{DATABASE_NAME}; SELECT COUNT(*) FROM terminus;").split("\n").last&.strip
    puts "   Sync progress: #{count} / #{SIMULATE_SIZE}"
    break if count == SIMULATE_SIZE.to_s

    sleep 0.1
    wait_times += 1

    next unless wait_times > MAX_RETRY

    puts "\n"
    puts '   Failed to retrieve enough data records in sink.'
    `#{FLINK_HOME}/bin/flink log `
    return false
  end

  puts "\n"
  puts '   Phase 1 complete. Test migration now...'
  `#{FLINK_HOME}/bin/flink stop #{current_job_id} --savepointPath #{Dir.pwd}/savepoints #{current_job_id}`
  exec_sql_source("source #{Dir.pwd}/_phase_2.sql")

  savepoint_file = `ls savepoints`.split("\n").last
  puts "   Submitting CDC jobs at #{to_version}..."
  submit_job_output = `bash ./cdc-versions/#{to_version}/bin/flink-cdc.sh --from-savepoint #{Dir.pwd}/savepoints/#{savepoint_file} --allow-nonRestored-state --flink-home #{FLINK_HOME} #{YAML_JOB_FILE}`
  puts "   #{submit_job_output}"
  new_job_id = submit_job_output.split("\n")[1].split.last
  puts "   Upgraded Job ID: #{new_job_id}"

  puts '   Checking Phase 2 sync progress...'
  wait_times = 0
  loop do
    count = exec_sql_sink("USE #{DATABASE_NAME}; SELECT COUNT(*) FROM terminus;").split("\n").last&.strip
    puts "   Sync progress: #{count} / #{SIMULATE_SIZE * 2}"
    break if count == (SIMULATE_SIZE * 2).to_s

    puts "\n"
    sleep 0.1
    wait_times += 1
    if wait_times > MAX_RETRY
      '❌ Failed to retrieve enough data records in sink.' if wait_times > MAX_RETRY
      return false
    end
  end
  true
end

def test_migration(from_version, to_version)
  puts "➡️ [MIGRATION] Testing migration from #{from_version} to #{to_version}..."
  puts "   with Flink #{FLINK_HOME}..."
  begin
    test_migration_chore from_version, to_version
    puts "✅ [MIGRATION] Successfully migrated from #{from_version} to #{to_version}!"
    true
  rescue NoMethodError
    puts "❌ [MIGRATION] Failed to migrate from #{from_version} to #{to_version}..."
    false
  end
end

version_list = %w[3.0.0 3.0.1 3.1.0 3.2-SNAPSHOT]
no_savepoint_versions = %w[3.0.0 3.0.1]
version_result = Hash.new('❓')

version_list.each_with_index do |old_version, old_index|
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
    if old_index > new_index
      table_line << ""
    else
      table_line << version_result[old_version + new_version]
    end
  end
  printable_result << table_line
end

puts Terminal::Table.new :rows => printable_result, :title => 'Migration Test Result'
