{ lib, ... }:

{
  virtualisation.memorySize = [ 1024 2048 ];
  virtualisation.diskSize = [ 2048 4096 ];

  # v2: avoid invalid startup-only combinations. etcd requires
  # election-timeout >= 5 * heartbeat-interval, so both election values are
  # valid for both heartbeat values.
  services.etcd.extraConf."HEARTBEAT_INTERVAL" = [ "100" "250" ];
  services.etcd.extraConf."ELECTION_TIMEOUT" = [ "1250" "2500" ];
  services.etcd.extraConf."SNAPSHOT_COUNT" = [ "10000" "100000" ];

  # v2: include quota values small enough to expose workload/configuration
  # incompatibilities after the cluster has started.
  services.etcd.extraConf."QUOTA_BACKEND_BYTES" = [ "2097152" "8388608" "67108864" ];
}
