{ lib, ... }:

# Minimal Kafka-cluster config for reproducing the large-message
# `RecordTooLargeException` class. Kafka starts and small-message checks pass,
# but a 1.5 MiB record exceeds the broker's 1 MiB message limit.
{
  virtualisation.memorySize = [ 2048 ];
  virtualisation.diskSize = [ 2048 ];

  services.apache-kafka.jvmOptions = [
    [ "-Xms256m" "-Xmx512m" ]
  ];

  services.apache-kafka.settings."offsets.topic.replication.factor" = [ 1 ];
  services.apache-kafka.settings."transaction.state.log.replication.factor" = [ 1 ];
  services.apache-kafka.settings."transaction.state.log.min.isr" = [ 1 ];
  services.apache-kafka.settings."min.insync.replicas" = [ 1 ];
  services.apache-kafka.settings."default.replication.factor" = [ 1 ];

  services.apache-kafka.settings."unclean.leader.election.enable" = [ false ];
  services.apache-kafka.settings."auto.create.topics.enable" = [ false ];
  services.apache-kafka.settings."log.retention.hours" = [ 1 ];
  services.apache-kafka.settings."log.segment.bytes" = [ 16777216 ];

  services.apache-kafka.settings."message.max.bytes" = [ 1048576 ];
  services.apache-kafka.settings."replica.fetch.max.bytes" = [ 4194304 ];

  services.apache-kafka.settings."num.network.threads" = [ 2 ];
  services.apache-kafka.settings."num.io.threads" = [ 4 ];
}
