{ pkgs, nodeName, ... }:

let
  nodeIds = {
    etcd1 = 1;
    etcd2 = 2;
    etcd3 = 3;
  };
  nodeId = nodeIds.${nodeName};
  cluster = [
    "etcd1=http://etcd1:2380"
    "etcd2=http://etcd2:2380"
    "etcd3=http://etcd3:2380"
  ];
in
{
  virtualisation.memorySize = 1024;
  virtualisation.diskSize = 2048;

  networking.firewall.allowedTCPPorts = [
    2379
    2380
  ];

  services.etcd = {
    enable = true;
    name = nodeName;
    dataDir = "/var/lib/etcd";
    listenClientUrls = [ "http://0.0.0.0:2379" ];
    advertiseClientUrls = [ "http://${nodeName}:2379" ];
    listenPeerUrls = [ "http://0.0.0.0:2380" ];
    initialAdvertisePeerUrls = [ "http://${nodeName}:2380" ];
    initialCluster = cluster;
    initialClusterState = "new";
    initialClusterToken = "topotestix-etcd-cluster";
    extraConf = {
      "INITIAL_ELECTION_TICK_ADVANCE" = "true";
      "HEARTBEAT_INTERVAL" = "100";
      "ELECTION_TIMEOUT" = "1000";
      "SNAPSHOT_COUNT" = "10000";
      "QUOTA_BACKEND_BYTES" = "67108864";
    };
  };

  environment.systemPackages = with pkgs; [
    etcd
    jq
    python3
  ];

  environment.variables = {
    ETCDCTL_API = "3";
    ETCDCTL_ENDPOINTS = "http://etcd1:2379,http://etcd2:2379,http://etcd3:2379";
  };
}
