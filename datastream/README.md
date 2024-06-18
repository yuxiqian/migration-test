# Flink CDC MigrationTestUtils

## DataStream Jobs
### Preparation

1. Install Ruby (macOS has embedded it by default)
2. (Optional) Run `gem install terminal-table` for better display

### Compile DataStream Jobs
3. Run `mvn clean package` to compile dummy DataStream jobs with specific version tags
4. Run `ruby run_migration_test.rb` to start testing