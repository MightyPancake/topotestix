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

  topic_roundtrip = {
    name = "kafka-topic-roundtrip";
    setup = ''
      def check_kafka_roundtrip(machine):
          machine.succeed(
              "echo 'topotestix-payload' | "
              "kafka-console-producer.sh --bootstrap-server localhost:9092 "
              "--topic topotestix-cluster 2>/dev/null"
          )
          machine.succeed(
              "kafka-console-consumer.sh --bootstrap-server localhost:9092 "
              "--topic topotestix-cluster --from-beginning --max-messages 1 "
              "--timeout-ms 10000 2>/dev/null | grep '^topotestix-payload$'"
          )
    '';
    check = ''
      _check("kafka-roundtrip-on-kafka1", check_kafka_roundtrip, kafka1)
      _check("kafka-roundtrip-on-kafka2", check_kafka_roundtrip, kafka2)
      _check("kafka-roundtrip-on-kafka3", check_kafka_roundtrip, kafka3)
    '';
  };

  service_still_up_after_delay = {
    name = "kafka-still-up-after-delay";
    setup = ''
      def check_kafka_still_up(machine):
          machine.succeed("sleep 30 && systemctl is-active apache-kafka")
    '';
    check = ''
      _check("kafka-still-up-kafka1", check_kafka_still_up, kafka1)
      _check("kafka-still-up-kafka2", check_kafka_still_up, kafka2)
      _check("kafka-still-up-kafka3", check_kafka_still_up, kafka3)
    '';
  };

  multi_topic_creation = {
    name = "kafka-multi-topic-creation";
    setup = ''
      def check_kafka_multi_topic(machine):
          for t in ("topotestix_a", "topotestix_b", "topotestix_c"):
              machine.succeed(
                  f"kafka-topics.sh --bootstrap-server localhost:9092 "
                  f"--create --if-not-exists --topic {t} "
                  f"--partitions 3 --replication-factor 3"
              )
          machine.succeed(
              "kafka-topics.sh --bootstrap-server localhost:9092 --list | "
              "grep -E '^(topotestix_a|topotestix_b|topotestix_c)$' | wc -l | grep '^3$'"
          )
    '';
    check = ''
      _check("kafka-multi-topic-on-kafka1", check_kafka_multi_topic, kafka1)
    '';
  };

  large_message_roundtrip = {
    name = "kafka-large-message-roundtrip";
    setup = ''
      def check_kafka_large_message_roundtrip(machine):
          status, out = machine.execute(r"""
      bash -euo pipefail 2>&1 <<'BASH'
      TOPIC=topotestix_large
      SIZE=1572864

      head -c "$SIZE" /dev/zero | tr '\000' 'x' > /tmp/topotestix-large-input
      printf '\n' >> /tmp/topotestix-large-input

      kafka-topics.sh --bootstrap-server localhost:9092 \
        --create --if-not-exists --topic "$TOPIC" \
        --partitions 3 --replication-factor 3

      kafka-console-producer.sh --bootstrap-server localhost:9092 \
        --topic "$TOPIC" \
        --producer-property max.request.size=4194304 \
        --producer-property batch.size=4194304 \
        --producer-property buffer.memory=8388608 \
        --producer-property acks=all \
        --producer-property delivery.timeout.ms=30000 \
        --producer-property request.timeout.ms=10000 \
        < /tmp/topotestix-large-input

      kafka-console-consumer.sh --bootstrap-server localhost:9092 \
        --topic "$TOPIC" --from-beginning --max-messages 1 --timeout-ms 20000 \
        --consumer-property max.partition.fetch.bytes=4194304 \
        --consumer-property fetch.max.bytes=4194304 \
        > /tmp/topotestix-large-consumed

      ACTUAL_SIZE=$(wc -c < /tmp/topotestix-large-consumed)
      if [ "$ACTUAL_SIZE" -lt "$SIZE" ]; then
        echo "large message roundtrip consumed too few bytes: expected_at_least=$SIZE actual=$ACTUAL_SIZE"
        exit 1
      fi
      BASH
          """, timeout=90)
          if status != 0:
              raise AssertionError(out[-4000:])
    '';
    check = ''
      _check("kafka-large-message-on-kafka1", check_kafka_large_message_roundtrip, kafka1)
    '';
  };
}
