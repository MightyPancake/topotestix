{ pkgs, nodeName, ... }:

let
  nodeIds = {
    kafka1 = 1;
    kafka2 = 2;
    kafka3 = 3;
  };
  nodeId = nodeIds.${nodeName};
  brokerAddress = "${nodeName}:9092";
in
{
  virtualisation.memorySize = 3072;
  virtualisation.diskSize = 4096;

  networking.firewall.allowedTCPPorts = [
    9092
    9093
  ];

  services.apache-kafka = {
    enable = true;
    clusterId = "4L6g3nShT-eMCtK--X86sw";
    formatLogDirs = true;
    formatLogDirsIgnoreFormatted = true;
    jvmOptions = [
      "-Xms256m"
      "-Xmx512m"
    ];
    settings = {
      "node.id" = nodeId;
      "process.roles" = [
        "broker"
        "controller"
      ];
      "controller.quorum.voters" = "1@kafka1:9093,2@kafka2:9093,3@kafka3:9093";
      "listeners" = [
        "PLAINTEXT://0.0.0.0:9092"
        "CONTROLLER://0.0.0.0:9093"
      ];
      "advertised.listeners" = [ "PLAINTEXT://${brokerAddress}" ];
      "listener.security.protocol.map" = "CONTROLLER:PLAINTEXT,PLAINTEXT:PLAINTEXT";
      "controller.listener.names" = "CONTROLLER";
      "inter.broker.listener.name" = "PLAINTEXT";
      "log.dirs" = [ "/var/lib/apache-kafka/logs" ];
      "offsets.topic.replication.factor" = 3;
      "transaction.state.log.replication.factor" = 3;
      "transaction.state.log.min.isr" = 2;
      "default.replication.factor" = 3;
      "min.insync.replicas" = 2;
      "group.initial.rebalance.delay.ms" = 0;
    };
  };

  environment.systemPackages = with pkgs; [
    apacheKafka
    coreutils
  ];
}
