machine1.wait_for_unit("apache-kafka")
machine1.wait_for_open_port(9092)

machine1.succeed(
    "kafka-topics.sh --bootstrap-server localhost:9092 "
    "--create --if-not-exists --topic topotestix-smoke "
    "--partitions 1 --replication-factor 1"
)
