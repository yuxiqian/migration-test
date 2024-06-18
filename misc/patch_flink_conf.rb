# frozen_string_literal: true

FLINK_HOME = ENV['FLINK_HOME']
throw 'Unspecified `FLINK_HOME` environment variable.' if FLINK_HOME.nil?

EXTRA_CONF = <<~EXTRACONF

taskmanager.numberOfTaskSlots: 10
parallelism.default: 4
execution.checkpointing.interval: 300
EXTRACONF

File.write("#{FLINK_HOME}/conf/flink-conf.yaml", EXTRA_CONF, mode: 'a+')