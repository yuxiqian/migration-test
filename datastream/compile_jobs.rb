# frozen_string_literal: true

JOB_VERSIONS = %w[2.4.2 3.0.0 3.0.1 3.1.0 3.1.1 3.2-SNAPSHOT]

JOB_VERSIONS.each do |version|
  puts "Compiling DataStream job for CDC #{version}"
  `cd datastream-#{version} && mvn clean package -DskipTests`
end

puts 'Done'