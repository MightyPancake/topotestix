# Kafka-cluster 50-seed sweep results

Date: 2026-06-13  
Target: `kafka-cluster`  
Command:

```bash
python3 -m topotestix.cli orchestrator sweep kafka-cluster --seeds 1..50 --project-root .
```

Console log:

```text
experiments/kafka-cluster-sweep-1-50-fixed-20260613.log
```

Machine-readable summary:

```text
experiments/kafka-cluster-sweep-1-50-fixed-20260613-summary.json
experiments/kafka-cluster-sweep-1-50-fixed-20260613-summary.txt
```

## Why this sweep is the valid one

An earlier 50-seed sweep failed 50/50 because the first version of the large-message property used an exact `cmp` against `kafka-console-consumer` output. Seed 3 showed that Kafka had actually accepted and consumed one large message, but the byte comparison still failed. That earlier sweep is treated as a property-design artifact and should not be used as thesis evidence.

The property was fixed to require a production-relevant condition instead:

- Produce a 1.5 MiB record with `acks=all`.
- Consume one record back.
- Require that the consumed output contains at least 1.5 MiB.

Validation before the fixed sweep:

| Seed | Expected | Result |
|---:|---|---|
| 3 | healthy large-message config should pass | passed 11/11 |
| 13 | `message.max.bytes = 1 MiB` should reject 1.5 MiB record | failed with `RecordTooLargeException` |

## Aggregate result

| Outcome | Count |
|---|---:|
| Passed | 13 |
| Failed | 37 |
| Total | 50 |

All failures were in one property:

```text
kafka-large-message-on-kafka1
```

The other 10 checks passed whenever they were reached:

- `kafka-multi-topic-on-kafka1`
- `kafka-still-up-kafka{1,2,3}`
- `kafka-roundtrip-on-kafka{1,2,3}`
- `kafka-topic-visible-from-kafka{1,2,3}`

## Failure classes

| Class | Count | Kafka exception | Production relevance |
|---|---:|---|---|
| Broker max-message limit too small | 18 | `RecordTooLargeException` | A workload sends messages larger than the broker's configured `message.max.bytes`. Producers fail even though the cluster is otherwise healthy. |
| Log segment size too small | 19 | `RecordBatchTooLargeException` | `log.segment.bytes` is smaller than the record batch. This is a realistic misconfiguration for large-payload workloads or compacted/batched producers. |
| Pass | 13 | n/a | Broker accepted and consumer received the 1.5 MiB message. |

No startup/OOM failures occurred in the fixed sweep. This is desirable: failures are data-plane/configuration failures after Kafka has started, not trivial boot failures.

## Seed lists

Passed seeds:

```text
2, 3, 6, 21, 24, 25, 26, 27, 29, 30, 38, 39, 42
```

Failed seeds:

```text
1, 4, 5, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 22, 23, 28, 31, 32, 33, 34, 35, 36, 37, 40, 41, 43, 44, 45, 46, 47, 48, 49, 50
```

## Representative failing runs

### `message.max.bytes` too small

Seed 13:

```text
run dir: .topotestix/runs/20260613-210143-kafka-cluster-seed-13-kafka-cluster-seed-13
message.max.bytes = 1048576
log.segment.bytes = 1048576
```

Report evidence:

```text
org.apache.kafka.common.errors.RecordTooLargeException:
The request included a message larger than the max message size the server will accept.
```

Interpretation: Kafka starts and normal small-message checks pass, but the large-message data path fails because the broker maximum message size is below workload requirements.

### `log.segment.bytes` too small

Seed 9:

```text
run dir: .topotestix/runs/20260613-204310-kafka-cluster-seed-9-kafka-cluster-seed-9
message.max.bytes = 4194304
log.segment.bytes = 1048576
```

Report evidence:

```text
org.apache.kafka.common.errors.RecordBatchTooLargeException:
The request included message batch larger than the configured segment size on the server.
```

Interpretation: The broker's message-size setting is high enough, but the log segment setting is still too small for the batch. This is a more subtle configuration interaction than a single low max-message limit.

## Notes for thesis interpretation

These are not Kafka implementation bugs. They are realistic configuration bugs / bad configuration interactions that TopoTestix discovers by varying distributed-system settings and checking properties.

The most valuable empirical claim is therefore:

> TopoTestix can automatically surface production-relevant Kafka misconfigurations that do not prevent the cluster from starting but do break specific workload properties, such as large-payload produce/consume behaviour.

This is stronger than the earlier startup-OOM finding because the system reaches a running state and only fails under a workload-specific data-plane property.

## Verification

After the runner/report fix and property adjustment:

```text
python unittest: 34/34 passed
nix flake check: passed
```
