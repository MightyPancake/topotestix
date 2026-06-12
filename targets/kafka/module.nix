{ pkgs, ... }:

{
  virtualisation.memorySize = 2048;
  virtualisation.diskSize = 4096;

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
      "node.id" = 1;
      "process.roles" = [
        "broker"
        "controller"
      ];
      "controller.quorum.voters" = "1@localhost:9093";
      "listeners" = [
        "PLAINTEXT://localhost:9092"
        "CONTROLLER://localhost:9093"
      ];
      "advertised.listeners" = [ "PLAINTEXT://localhost:9092" ];
      "listener.security.protocol.map" = "CONTROLLER:PLAINTEXT,PLAINTEXT:PLAINTEXT";
      "controller.listener.names" = "CONTROLLER";
      "inter.broker.listener.name" = "PLAINTEXT";
      "log.dirs" = [ "/var/lib/apache-kafka/logs" ];
      "offsets.topic.replication.factor" = 1;
      "transaction.state.log.replication.factor" = 1;
      "transaction.state.log.min.isr" = 1;
      "group.initial.rebalance.delay.ms" = 0;
    };
  };

  environment.systemPackages = with pkgs; [
    apacheKafka
    coreutils
  ];
}
