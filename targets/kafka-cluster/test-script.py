start_all()

for machine in [kafka1, kafka2, kafka3]:
    machine.wait_for_unit("apache-kafka")
    machine.wait_for_open_port(9092)

kafka1.succeed(
    "kafka-topics.sh --bootstrap-server kafka1:9092 "
    "--create --if-not-exists --topic topotestix-cluster "
    "--partitions 3 --replication-factor 3"
)
