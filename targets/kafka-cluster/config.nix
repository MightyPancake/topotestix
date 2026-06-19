{ lib, ... }:

{
  # Resources — small values surface OOM and slow-start failures.
  virtualisation.memorySize = [ 2048 3072 4096 ];
  virtualisation.diskSize   = [ 2048 4096 8192 ];

  # JVM heap — three variants. The 512MB max is tight enough to OOM under
  # roundtrip load, surfacing JVM heap pressure as a real failure mode.
  # The fuzzer picks one inner list per seed, so the resolved value is a
  # list of strings (matches the apache-kafka module's listOf str type).
  services.apache-kafka.jvmOptions = [
    [ "-Xms256m"  "-Xmx512m"  ]
    [ "-Xms512m"  "-Xmx1024m" ]
    [ "-Xms1024m" "-Xmx1536m" ]
  ];

  # Cluster-level tunables that interact with the 3-node topology.
  services.apache-kafka.settings."offsets.topic.replication.factor"         = [ 1 3 ];
  services.apache-kafka.settings."transaction.state.log.replication.factor" = [ 1 3 ];
  services.apache-kafka.settings."transaction.state.log.min.isr"             = [ 1 2 ];
  services.apache-kafka.settings."min.insync.replicas"                      = [ 1 2 ];
  services.apache-kafka.settings."default.replication.factor"               = [ 1 3 ];

  # Behavior knobs with known fragility.
  services.apache-kafka.settings."unclean.leader.election.enable" = [ false true ];
  services.apache-kafka.settings."auto.create.topics.enable"       = [ false true ];
  services.apache-kafka.settings."log.retention.hours"             = [ 1 24 168 ];
  services.apache-kafka.settings."log.segment.bytes"               = [ 1048576 16777216 ];

  # Data-plane payload limits. The large-message property below sends a 1.5 MiB
  # record with acks=all. 1 MiB limits should fail at produce/replication time;
  # 2 MiB and 4 MiB limits should generally pass if the cluster is healthy.
  services.apache-kafka.settings."message.max.bytes"       = [ 1048576 2097152 4194304 ];
  services.apache-kafka.settings."replica.fetch.max.bytes" = [ 1048576 2097152 4194304 ];

  # Threading.
  services.apache-kafka.settings."num.network.threads" = [ 2 3 ];
  services.apache-kafka.settings."num.io.threads"      = [ 4 6 ];
}
