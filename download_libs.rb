# frozen_string_literal: true

VERSIONS = {
  '3.0.0': {
    tar: 'https://github.com/ververica/flink-cdc-connectors/releases/download/release-3.0.0/flink-cdc-3.0.0-bin.tar.gz',
    connectors: %w[
      https://repo1.maven.org/maven2/com/ververica/flink-cdc-pipeline-connector-doris/3.0.0/flink-cdc-pipeline-connector-doris-3.0.0.jar
      https://repo1.maven.org/maven2/com/ververica/flink-cdc-pipeline-connector-mysql/3.0.0/flink-cdc-pipeline-connector-mysql-3.0.0.jar
      https://repo1.maven.org/maven2/com/ververica/flink-cdc-pipeline-connector-starrocks/3.0.0/flink-cdc-pipeline-connector-starrocks-3.0.0.jar
      https://repo1.maven.org/maven2/com/ververica/flink-cdc-pipeline-connector-values/3.0.0/flink-cdc-pipeline-connector-values-3.0.0.jar
    ]
  },
  '3.0.1': {
    tar: 'https://github.com/ververica/flink-cdc-connectors/releases/download/release-3.0.1/flink-cdc-3.0.1-bin.tar.gz',
    connectors: %w[
      https://repo1.maven.org/maven2/com/ververica/flink-cdc-pipeline-connector-doris/3.0.1/flink-cdc-pipeline-connector-doris-3.0.1.jar
      https://repo1.maven.org/maven2/com/ververica/flink-cdc-pipeline-connector-mysql/3.0.1/flink-cdc-pipeline-connector-mysql-3.0.1.jar
      https://repo1.maven.org/maven2/com/ververica/flink-cdc-pipeline-connector-starrocks/3.0.1/flink-cdc-pipeline-connector-starrocks-3.0.1.jar
      https://repo1.maven.org/maven2/com/ververica/flink-cdc-pipeline-connector-values/3.0.1/flink-cdc-pipeline-connector-values-3.0.1.jar
    ]
  },
  '3.1.0': {
    tar: 'https://www.apache.org/dyn/closer.lua/flink/flink-cdc-3.1.0/flink-cdc-3.1.0-bin.tar.gz',
    connectors: %w[
      https://repo1.maven.org/maven2/org/apache/flink/flink-cdc-pipeline-connector-mysql/3.1.0/flink-cdc-pipeline-connector-mysql-3.1.0.jar
      https://repo1.maven.org/maven2/org/apache/flink/flink-cdc-pipeline-connector-doris/3.1.0/flink-cdc-pipeline-connector-doris-3.1.0.jar
      https://repo1.maven.org/maven2/org/apache/flink/flink-cdc-pipeline-connector-starrocks/3.1.0/flink-cdc-pipeline-connector-starrocks-3.1.0.jar
      https://repo1.maven.org/maven2/org/apache/flink/flink-cdc-pipeline-connector-kafka/3.1.0/flink-cdc-pipeline-connector-kafka-3.1.0.jar
      https://repo1.maven.org/maven2/org/apache/flink/flink-cdc-pipeline-connector-paimon/3.1.0/flink-cdc-pipeline-connector-paimon-3.1.0.jar
    ]
  }
}.freeze

def download_or_get(link)
  `mkdir -p cache`
  file_name = "cache/#{File.basename(link)}"
  if File.exist? file_name
    puts "#{file_name} exists, skip download"
    return file_name
  end
  `wget #{link} -O #{file_name}`
  file_name
end

M2_REPO = '~/.m2/repository/org/apache/flink'
FILES = %w[
  dist
  pipeline-connector-kafka
  pipeline-connector-mysql
  pipeline-connector-doris
  pipeline-connector-paimon
  pipeline-connector-starrocks
].freeze
def place_snapshot_connector(version)
  `mkdir -p cdc-versions/#{version}/lib`
  `cp -r ../flink-cdc/flink-cdc-dist/src/main/flink-cdc-bin/* cdc-versions/#{version}/`

  puts 'Compiling CDC project...'
  `cd ../flink-cdc && mvn install -DskipTests`

  FILES.each do |lib|
    `cp #{M2_REPO}/flink-cdc-#{lib}/#{version}/flink-cdc-#{lib}-#{version}.jar cdc-versions/#{version}/lib/`
  end
end

def download_libs
  `rm -rf cdc-versions`
  VERSIONS.each do |version, links|
    `mkdir -p cdc-versions/#{version}`
    file_name = download_or_get(links[:tar])
    `tar --strip-components=1 -xzvf #{file_name} -C cdc-versions/#{version}`
    links[:connectors].each do |link|
      jar_file_name = download_or_get(link)
      `cp #{jar_file_name} cdc-versions/#{version}/lib/`
    end
  end
end

download_libs
place_snapshot_connector '3.2-SNAPSHOT'
puts 'Done'
