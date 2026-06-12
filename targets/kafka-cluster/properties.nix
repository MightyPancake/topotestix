{ lib }:

{
  topic_visible_from_all_brokers = {
    name = "kafka-topic-visible-from-all-brokers";
    setup = ''
      def check_kafka_topic_visible(machine):
          machine.succeed("kafka-topics.sh --bootstrap-server localhost:9092 --list | grep '^topotestix-cluster$'")
    '';
    check = ''
      _check("kafka-topic-visible-from-kafka1", check_kafka_topic_visible, kafka1)
      _check("kafka-topic-visible-from-kafka2", check_kafka_topic_visible, kafka2)
      _check("kafka-topic-visible-from-kafka3", check_kafka_topic_visible, kafka3)
    '';
  };
}
