{
  nginx = {
    description = "Single-node nginx smoke target";
    topologyTarget = ./topology/single-machine.nix;
    configTarget = ./config/nginx.nix;
    baseModule = ./nginx/module.nix;
    testScript = ./nginx/test-script.py;
    properties = ./nginx/properties.nix;
    reportNode = "machine1";
  };

  kafka = {
    description = "Single-node Kafka KRaft smoke target";
    topologyTarget = ./topology/single-machine.nix;
    configTarget = ./config/kafka.nix;
    baseModule = ./kafka/module.nix;
    testScript = ./kafka/test-script.py;
    properties = ./kafka/properties.nix;
    reportNode = "machine1";
  };

  kafka-cluster = {
    description = "Three-node Kafka KRaft cluster smoke target";
    topologyTarget = ./topology/kafka-cluster.nix;
    configTarget = ./config/kafka-cluster.nix;
    baseModule = ./kafka-cluster/module.nix;
    testScript = ./kafka-cluster/test-script.py;
    properties = ./kafka-cluster/properties.nix;
    reportNode = "kafka1";
  };
}
