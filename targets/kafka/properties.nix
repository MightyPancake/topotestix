{ lib }:

{
  topic_roundtrip = {
    name = "kafka-topic-roundtrip";
    setup = ''
      def check_kafka_topic_roundtrip(machine):
          machine.succeed("kafka-topics.sh --bootstrap-server localhost:9092 --list | grep '^topotestix-smoke$'")
    '';
    check = ''
      _check("kafka-topic-roundtrip", check_kafka_topic_roundtrip, machine1)
    '';
  };
}
