# frozen_string_literal: true

# Use your own Flink home path instead
FLINK_HOME = '~/Documents/Flink/flink-1.18.1'
SOURCE_PORT = 3306
DATABASE_NAME = 'fallen'
TABLES = %w[angel gabriel girl].freeze
SIMULATE_SIZE = 4

puts 'Preparing test data...'

File.open('_phase_1.sql', 'w') do |f|
  1.upto(SIMULATE_SIZE).each do |num|
    f.write("INSERT INTO #{TABLES.sample(1)[0]} VALUES (#{num}, 'num_#{num}');\n")
  end
end

File.open('_phase_2.sql', 'w') do |f|
  (SIMULATE_SIZE + 1).upto(SIMULATE_SIZE * 2).each do |num|
    f.write("INSERT INTO #{TABLES.sample(1)[0]} VALUES (#{num}, 'num_#{num}');\n")
  end
end

File.open('_phase_3.sql', 'w') do |f|
  (SIMULATE_SIZE * 2 + 1).upto(SIMULATE_SIZE * 3).each do |num|
    f.write("INSERT INTO #{TABLES.sample(1)[0]} VALUES (#{num}, 'num_#{num}');\n")
  end
end

def exec_sql_source(sql)
  `mysql -h 127.0.0.1 -P#{SOURCE_PORT} -uroot --skip-password -e "USE #{DATABASE_NAME}; #{sql}" 2>/dev/null`
end

def test_migration_chore(from_version, to_version)
  yaml_job_file_1 = 'conf/pipeline-to-values-stage-1.yaml'
  yaml_job_file_2 = 'conf/pipeline-to-values-stage-2.yaml'
  puts '   Cleaning up stale jobs...'
  `#{FLINK_HOME}/bin/flink list`.split("\n").each do |line|
    job_id = line.split(' : ')[1]
    `#{FLINK_HOME}/bin/flink cancel #{job_id}` unless job_id.nil?
    puts "Killed job #{line}" unless job_id.nil?
  end

  `rm -rf savepoints`
  puts '   Waiting for source to start up...'
  next until exec_sql_source("SELECT '1';") == "1\n1\n"

  TABLES.each do |table_name|
    exec_sql_source("DROP TABLE IF EXISTS #{table_name};")
    exec_sql_source("CREATE TABLE #{table_name} (ID INT NOT NULL, NAME VARCHAR(17), PRIMARY KEY (ID));")
  end
  exec_sql_source("source #{Dir.pwd}/_phase_1.sql")

  puts "   Submitting CDC jobs at #{from_version}..."
  submit_job_output = `bash ./cdc-versions/#{from_version}/bin/flink-cdc.sh --flink-home #{FLINK_HOME} #{yaml_job_file_1}`
  puts "   #{submit_job_output}"
  current_job_id = submit_job_output.split("\n")[1].split.last
  puts "   Current Job ID: #{current_job_id}"

  sleep 10

  puts "\n"
  puts '   Phase 1 complete. Test migration now...'
  `#{FLINK_HOME}/bin/flink stop #{current_job_id} --savepointPath #{Dir.pwd}/savepoints #{current_job_id}`
  exec_sql_source("source #{Dir.pwd}/_phase_2.sql")

  savepoint_file = `ls savepoints`.split("\n").last
  puts "   Submitting CDC jobs at #{to_version}..."
  submit_job_output = `bash ./cdc-versions/#{to_version}/bin/flink-cdc.sh --from-savepoint #{Dir.pwd}/savepoints/#{savepoint_file} --allow-nonRestored-state --flink-home #{FLINK_HOME} #{yaml_job_file_2}`
  puts "   #{submit_job_output}"
  new_job_id = submit_job_output.split("\n")[1].split.last
  puts "   Upgraded Job ID: #{new_job_id}"

  # Wait for job to start
  sleep 10
  exec_sql_source("source #{Dir.pwd}/_phase_3.sql")
  sleep 10
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

puts 'Restarting cluster...'
`#{FLINK_HOME}/bin/stop-cluster.sh`
`#{FLINK_HOME}/bin/start-cluster.sh`
test_migration '3.1-SNAPSHOT', '3.2-SNAPSHOT'
