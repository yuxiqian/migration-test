# frozen_string_literal: true

# Use your own Flink home path instead
FLINK_HOME = '~/Documents/Flink/flink-1.18.1'
SOURCE_PORT = 3306
DATABASE_NAME = 'fallen'

PRE_TABLE = %w[alice bob chris].freeze
POST_TABLE = %w[dorothy eve faye].freeze
ALL_TABLES = PRE_TABLE + POST_TABLE

SIMULATE_SIZE = 4

puts 'Preparing test data...'

File.open('_phase_1.sql', 'w') do |f|
  1.upto(SIMULATE_SIZE).each do |num|
    f.write("INSERT INTO #{PRE_TABLE.sample(1)[0]} VALUES (#{num}, 'num_#{num}');\n")
  end
end

File.open('_phase_2.sql', 'w') do |f|
  (SIMULATE_SIZE + 1).upto(SIMULATE_SIZE * 2).each do |num|
    f.write("INSERT INTO #{ALL_TABLES.sample(1)[0]} VALUES (#{num}, 'num_#{num}');\n")
  end
end

File.open('_phase_3.sql', 'w') do |f|
  (SIMULATE_SIZE * 2 + 1).upto(SIMULATE_SIZE * 3).each do |num|
    f.write("INSERT INTO #{ALL_TABLES.sample(1)[0]} VALUES (#{num}, 'num_#{num}');\n")
  end
end

def exec_sql_source(sql)
  `mysql -h 127.0.0.1 -P#{SOURCE_PORT} -uroot --skip-password -e "USE #{DATABASE_NAME}; #{sql}" 2>/dev/null`
end

def test_migration_chore(from_version, to_version)
  yaml_job_file = 'conf/add-table-test.yaml'
  puts '   Cleaning up stale jobs...'
  `#{FLINK_HOME}/bin/flink list`.split("\n").each do |line|
    job_id = line.split(' : ')[1]
    `#{FLINK_HOME}/bin/flink cancel #{job_id}` unless job_id.nil?
    puts "Killed job #{line}" unless job_id.nil?
  end

  `rm -rf savepoints`
  puts '   Waiting for source to start up...'
  next until exec_sql_source("SELECT '1';") == "1\n1\n"

  ALL_TABLES.each do |table_name|
    exec_sql_source("DROP TABLE IF EXISTS #{table_name};")
  end

  PRE_TABLE.each do |table_name|
    exec_sql_source("CREATE TABLE #{table_name} (ID INT NOT NULL, NAME VARCHAR(17), PRIMARY KEY (ID));")
  end
  exec_sql_source("source #{Dir.pwd}/_phase_1.sql")

  puts "   Submitting CDC jobs at #{from_version}..."
  submit_job_output = `bash ./cdc-versions/#{from_version}/bin/flink-cdc.sh --flink-home #{FLINK_HOME} #{yaml_job_file}`
  puts "   #{submit_job_output}"
  current_job_id = submit_job_output.split("\n")[1].split.last
  puts "   Current Job ID: #{current_job_id}"

  sleep 10

  puts "\n"
  puts '   Phase 1 complete. Test adding table now...'

  POST_TABLE.each do |table_name|
    exec_sql_source("CREATE TABLE #{table_name} (ID INT NOT NULL, NAME VARCHAR(17), PRIMARY KEY (ID));")
  end

  exec_sql_source("source #{Dir.pwd}/_phase_2.sql")
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
test_migration '3.2-SNAPSHOT', '3.2-SNAPSHOT'
