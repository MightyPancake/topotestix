# Kafka-cluster case study: workload-specific configuration failures

This case study summarizes the Kafka-cluster empirical result after isolating minimized repro configurations for the two observed failure classes.

## Thesis framing

These are **not Kafka implementation bugs**. They are production-relevant configuration/workload incompatibilities found automatically by TopoTestix.

The important observation is:

> Kafka starts successfully and passes basic smoke/data-plane checks, but fails a workload-specific large-message produce/consume property under particular configurations.

That is the thesis-relevant value: TopoTestix finds failures that ordinary startup checks would miss.

## Property under test

The distinguishing property is:

```text
kafka-large-message-on-kafka1
```

It checks that a Kafka cluster can handle a 1.5 MiB record:

1. create a topic,
2. produce a 1.5 MiB payload with `acks=all`,
3. consume one record back,
4. require at least 1.5 MiB of consumed output.

The other 10 properties are basic liveness and small-message checks:

- topic visibility from each broker,
- small-message roundtrip from each broker,
- service liveness after a delay,
- multi-topic creation.

In the minimized repros below, all 10 of those checks pass. Only the large-message workload property fails.

## Sweep result

Fixed 50-seed sweep:

```text
experiments/kafka-cluster-sweep-1-50-fixed-20260613.md
experiments/kafka-cluster-sweep-1-50-fixed-20260613-summary.json
experiments/kafka-cluster-sweep-1-50-fixed-20260613-summary.txt
experiments/kafka-cluster-sweep-1-50-fixed-20260613.log
```

Aggregate:

| Outcome | Count |
|---|---:|
| Passed | 13 |
| Failed | 37 |
| Total | 50 |

Failure classes:

| Class | Count | Exception |
|---|---:|---|
| Broker maximum message size too small | 18 | `RecordTooLargeException` |
| Log segment size too small | 19 | `RecordBatchTooLargeException` |

## Repro 1: broker `message.max.bytes` too small

Original representative seed: `13`.

Raw generic shrink attempt:

```text
experiments/kafka-cluster-shrink-seed-13.log
```

Important: this raw shrink attempt is **not** used as the final minimized repro because Kafka's dotted setting names expose a current choice-path limitation in the generic shrinker. The thesis should use the validated class-isolating minimized config below.

Class-isolating minimized config target:

```text
experiments/kafka-cluster-min-message-max.nix
```

Validation log:

```text
experiments/kafka-cluster-min-message-max-run.log
```

Run directory:

```text
.topotestix/runs/20260615-172715-kafka-cluster-seed-1-kafka-cluster-min-message-max
```

Reproduce:

```bash
python3 -m topotestix.cli orchestrator run kafka-cluster \
  --seed 1 \
  --name kafka-cluster-min-message-max \
  --project-root . \
  --config-target experiments/kafka-cluster-min-message-max.nix
```

Minimized relevant settings:

```text
message.max.bytes = 1048576       # 1 MiB
log.segment.bytes = 16777216      # 16 MiB, not the limiting factor
replica.fetch.max.bytes = 4194304 # 4 MiB, not the limiting factor
large test record = 1572864       # 1.5 MiB
```

Observed failure:

```text
org.apache.kafka.common.errors.RecordTooLargeException:
The request included a message larger than the max message size the server will accept.
```

Observed passing checks in the same run:

```text
PASS kafka-multi-topic-on-kafka1
PASS kafka-still-up-kafka1
PASS kafka-still-up-kafka2
PASS kafka-still-up-kafka3
PASS kafka-roundtrip-on-kafka1
PASS kafka-roundtrip-on-kafka2
PASS kafka-roundtrip-on-kafka3
PASS kafka-topic-visible-from-kafka1
PASS kafka-topic-visible-from-kafka2
PASS kafka-topic-visible-from-kafka3
```

Interpretation:

Kafka is healthy for ordinary cluster operations and small records, but the configured broker maximum message size is incompatible with a workload that sends 1.5 MiB records.

## Repro 2: `log.segment.bytes` too small

Original representative seed: `9`.

Class-preserving shrink/validation log:

```text
experiments/kafka-cluster-shrink-seed-9.log
experiments/kafka-cluster-min-log-segment-run.log
```

Class-isolating minimized config target:

```text
experiments/kafka-cluster-min-log-segment.nix
```

Run directory:

```text
.topotestix/runs/20260615-173157-kafka-cluster-seed-1-kafka-cluster-min-log-segment
```

Reproduce:

```bash
python3 -m topotestix.cli orchestrator run kafka-cluster \
  --seed 1 \
  --name kafka-cluster-min-log-segment \
  --project-root . \
  --config-target experiments/kafka-cluster-min-log-segment.nix
```

Minimized relevant settings:

```text
message.max.bytes = 4194304       # 4 MiB, high enough for the record
log.segment.bytes = 1048576       # 1 MiB, too small for the batch
replica.fetch.max.bytes = 4194304 # 4 MiB, not the limiting factor
large test record = 1572864       # 1.5 MiB
```

Observed failure:

```text
org.apache.kafka.common.errors.RecordBatchTooLargeException:
The request included message batch larger than the configured segment size on the server.
```

Observed passing checks in the same run:

```text
PASS kafka-multi-topic-on-kafka1
PASS kafka-still-up-kafka1
PASS kafka-still-up-kafka2
PASS kafka-still-up-kafka3
PASS kafka-roundtrip-on-kafka1
PASS kafka-roundtrip-on-kafka2
PASS kafka-roundtrip-on-kafka3
PASS kafka-topic-visible-from-kafka1
PASS kafka-topic-visible-from-kafka2
PASS kafka-topic-visible-from-kafka3
```

Interpretation:

This is the stronger Kafka example. The obvious message-size limit is high enough, but another related setting, `log.segment.bytes`, still rejects the record batch. This demonstrates a non-obvious configuration interaction.

## Note on shrinking

The generic TopoTestix shrinker did **not** produce trustworthy final Kafka minimizations for these two case-study failures.

There are two reasons:

1. **Failure preservation is not failure-class preservation.** The shrinker currently keeps any candidate that still fails. For seed 9, unconstrained shrinking can reduce `message.max.bytes` and collapse the distinct `RecordBatchTooLargeException` / `log.segment.bytes` failure into the simpler `RecordTooLargeException` class.
2. **Kafka dotted setting names expose a choice-path limitation.** Kafka settings use quoted Nix attribute names containing dots, such as `"message.max.bytes"`. TopoTestix choice paths also use dots as separators, so command-line choice overrides for those paths are ambiguous. Some raw shrink attempts produced `0/0` property reports due to Nix/build failures rather than the intended Kafka property failure.

For that reason, the case study uses validated class-isolating minimized config targets instead of claiming automatic shrinker minimality:

```text
experiments/kafka-cluster-min-message-max.nix
experiments/kafka-cluster-min-log-segment.nix
```

These configs are minimal in the practical thesis sense: all unrelated options are fixed to simple baseline values, and only the failure-causing size constraint remains. They were validated by real runs where 10/11 properties passed and only the large-message property failed with the intended Kafka exception.

## Thesis-safe conclusion

Use this wording:

> The Kafka experiment shows that TopoTestix can find configuration-dependent workload property violations in a real distributed system. The detected cases are not Kafka implementation defects. Rather, they are realistic misconfigurations where the cluster starts and passes basic checks, but a large-message workload fails because related Kafka size limits are incompatible with the workload.

Avoid this wording:

> TopoTestix found Kafka bugs.
