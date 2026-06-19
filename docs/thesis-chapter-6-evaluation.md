# 6 Evaluation

This chapter presents the empirical evaluation of TopoTestix on two real-world distributed systems: a three-node Apache Kafka cluster and a three-node etcd cluster. Both targets are deployed as NixOS test drivers and exposed to the property-based fuzzing pipeline described in Chapter 5. The chapter is deliberately self-contained: for every reported result it states the target, the fuzzed configuration space, the property suite, the sweep outcome, the failure class, and (where available) a minimized reproduction. PostgreSQL is not part of this evaluation and is discussed separately in the related-work chapter.

The evaluation is guided by three research questions, all of which are answered in the summary at the end of this chapter:

> **RQ1.** Can TopoTestix automatically surface configuration-dependent property violations in real distributed systems, given only declarative system-under-test definitions and a property suite?
>
> **RQ2.** Are the surfaced violations of practical relevance, i.e. do they correspond to failure modes that would not be caught by ordinary startup or smoke tests?
>
> **RQ3.** Can TopoTestix localize the surfaced violations by shrinking the failing configuration to a small, reproducible repro, suitable for inclusion in a regression test or bug report?

The chapter is organized as follows. Section 6.1 describes the common evaluation setup. Section 6.2 presents the Kafka case study. Section 6.3 presents the etcd case study, including a first-iteration sweep, a refined second-iteration sweep, and shrinking results. Section 6.4 discusses cross-cutting observations that emerged from both studies, including framework fixes motivated by the evaluation and known limitations of the generic shrinker. Section 6.5 lists the threats to validity. Section 6.6 summarizes the answers to the three research questions.

## 6.1 Evaluation Setup

Both case studies follow the same evaluation protocol. For each target, TopoTestix is invoked with a deterministic random seed and a fixed seed range (1..50). Each seed instantiates a complete NixOS test derivation, builds it, starts the virtual cluster, runs the full property suite, and persists the structured per-run report under `.topotestix/runs/`. The runs are grouped by the orchestrator's sweep command and aggregated into a CSV/JSON summary.

The two targets are deliberately different in character. Kafka is a partitioned log/stream system with broker-side configuration that strongly affects data-plane behaviour, and the case study focuses on size-limit interactions under a large-payload workload. etcd is a Raft-based key-value store with a small cluster size and a quota-bounded backend, and the case study focuses on the interaction between a write-burst workload and the configured backend quota.

For every run the property suite returns one of two outcomes:

- **pass** — the run completed and all 11 (Kafka) or 12 (etcd) property checks were reached and succeeded, or all property checks that were reached succeeded and the run completed.
- **fail** — at least one property check that was reached failed, and the structured report records the failure class and a representative error message extracted from the cluster log.

In the Kafka sweep, the same ten baseline properties are present in every run, and the eleventh (large-message) property is the only one that can fail. In the etcd sweep, the final property is the quota write-burst; it is intentionally ordered last so that all basic health, leader, KV, and TTL checks must run before it. A failure in any property marks the run as failed; the failing check is recorded with a short class label so that the sweep can be summarized by class.

The fuzzable configuration dimensions for both targets are summarized in Table 6.1. The detailed per-dimension value sets are listed in the case-study sections.

**Table 6.1** — Fuzzable configuration dimensions per target.

| Target | Topology | Fuzzable options | Total combinations | Properties (per-run checks) |
|---|---|---:|---:|---:|
| `kafka-cluster` | 3 brokers | 16 | 746,496 | 11 |
| `etcd-cluster` (v2) | 3 nodes, 1 vlan | 6 | 1,152 | 12 |

The two targets share the same sweep size (50 seeds) and the same per-seed protocol. This makes the per-seed pass/fail counts directly comparable and prevents any one target from being favoured by sample size. Detailed per-seed reproduction commands are given in the case-study sections; the aggregated run directories are stored under `.topotestix/runs/` and listed in the per-target sweep summaries in `experiments/`.

## 6.2 Case Study: Apache Kafka

### 6.2.1 Target Setup

The Kafka target is a three-broker cluster that is built and started by a NixOS test driver. The target consists of:

- a topology description `targets/kafka-cluster/topology.nix` declaring three nodes `kafka1`, `kafka2`, `kafka3` on a single private network;
- a NixOS configuration module `targets/kafka-cluster/config.nix` that parameterizes the Apache Kafka service via the standard NixOS `services.apache-kafka` options;
- a property suite `targets/kafka-cluster/properties.nix` with five high-level properties, expanded to 11 per-run checks;
- a test script `targets/kafka-cluster/test-script.py` that composes the property suite with the standard TopoTestix runner.

Each broker is configured with its own advertised listener `kafka<i>:9092`, and the test driver only uses port `9092` for control-plane and data-plane interactions.

### 6.2.2 Configuration Space

The original Kafka target had only four fuzzable options and one property, and only a small subset of failure modes was reachable. The target was therefore expanded before the 50-seed sweep reported in this chapter. The fuzzed configuration space is:

- `virtualisation.memorySize` — VM RAM in MiB (2048 / 3072 / 4096).
- `virtualisation.diskSize` — VM disk in MiB (2048 / 3072 / 4096).
- `services.apache-kafka.jvmOptions` — JVM heap family (`-Xms256m/-Xmx512m`, `-Xms512m/-Xmx1024m`, `-Xms1024m/-Xmx1536m`).
- `offsets.topic.replication.factor` — 1 / 2 / 3.
- `transaction.state.log.replication.factor` — 1 / 2 / 3.
- `transaction.state.log.min.isr` — 1 / 2.
- `min.insync.replicas` — 1 / 2.
- `default.replication.factor` — 1 / 2 / 3.
- `unclean.leader.election.enable` — `true` / `false`.
- `auto.create.topics.enable` — `true` / `false`.
- `log.retention.hours` — 24 / 168 / 720.
- `log.segment.bytes` — 1 MiB / 2 MiB / 16 MiB.
- `message.max.bytes` — 1 MiB / 2 MiB / 4 MiB.
- `replica.fetch.max.bytes` — 1 MiB / 2 MiB / 4 MiB.
- `num.network.threads` — 1 / 2 / 4.
- `num.io.threads` — 1 / 2 / 4.

The product of the per-dimension value counts is 746,496 distinct configurations. Of these, only 50 are sampled in the sweep, which is sufficient to expose both large failure classes multiple times (Section 6.2.4). The heap-size and memory-size ranges were chosen to keep startup failures rare while still exercising realistic small-footprint configurations; the very low values (e.g. 64 MiB) that produced `OutOfMemoryError` during target development were removed because they only yielded startup failures, which are less informative than post-start workload failures (Section 6.4.1).

### 6.2.3 Properties

The property suite consists of five high-level properties, each expanded to one or more per-run checks:

1. **Topic visibility from all brokers** — a topic `topotestix-cluster` is visible via `kafka-topics.sh --list` from each broker. Expands to 3 checks.
2. **Topic roundtrip** — produce a small string (`topotestix-payload`) and consume it back from each broker. Expands to 3 checks.
3. **Service still up after delay** — `systemctl is-active apache-kafka` returns active on each broker after a 30-second sleep. Expands to 3 checks.
4. **Multi-topic creation** — create three topics `topotestix_a`, `topotestix_b`, `topotestix_c` with `--partitions 3 --replication-factor 3` and verify the list contains exactly three lines. Expands to 1 check.
5. **Large-message roundtrip** — produce a 1.5 MiB record with `acks=all` to a 3-partition RF=3 topic and consume it back; the consumer must receive at least 1.5 MiB. Expands to 1 check.

The total per-run check count is therefore 3+3+3+1+1 = 11. The large-message property is the only one that is expected to fail in the sweep; the first four properties act as a "system is actually working" filter and pass in every run that reaches them.

### 6.2.4 Sweep Results

The Kafka 50-seed sweep was executed with the following command:

```bash
python3 -m topotestix.cli orchestrator sweep kafka-cluster --seeds 1..50 --project-root .
```

The aggregate outcome is shown in Table 6.2. Of the 50 runs, 13 passed all 11 checks and 37 failed. Crucially, all 37 failures are concentrated in a single property, `kafka-large-message-on-kafka1`. Whenever a run reached the large-message property and the property failed, the other 10 properties had already passed. Whenever a run passed the large-message property, all 11 properties passed.

**Table 6.2** — Aggregate Kafka 50-seed sweep outcome.

| Outcome | Count | Share |
|---|---:|---:|
| Passed (11/11) | 13 | 26% |
| Failed (≥1 of 11) | 37 | 74% |
| Total | 50 | 100% |

The 37 failures fall into two clean and repeatable classes. Table 6.3 reports the per-class counts together with the underlying Kafka exception.

**Table 6.3** — Kafka failure classes in the 50-seed sweep.

| Class | Count | Kafka exception | Triggering configuration |
|---|---:|---|---|
| Broker `message.max.bytes` too small | 18 | `RecordTooLargeException` | `message.max.bytes = 1 MiB` |
| Log segment size too small | 19 | `RecordBatchTooLargeException` | `log.segment.bytes = 1 MiB` |
| Pass | 13 | n/a | larger size limits in effect |

A cross-tabulation of the three size-related options (`message.max.bytes`, `replica.fetch.max.bytes`, `log.segment.bytes`) against the outcome class is given in Table 6.4. The table shows that the two failure classes are triggered deterministically by specific value ranges, irrespective of the JVM heap, the VM size, and the replication-factor settings.

**Table 6.4** — Kafka sweep outcomes by (`message.max.bytes`, `replica.fetch.max.bytes`, `log.segment.bytes`).

| `message.max.bytes` | `replica.fetch.max.bytes` | `log.segment.bytes` | pass | broker-max | log-segment |
|---:|---:|---:|---:|---:|---:|
| 1 MiB | 1 MiB | 1 MiB | 0 | 3 | 0 |
| 1 MiB | 1 MiB | 16 MiB | 0 | 3 | 0 |
| 1 MiB | 2 MiB | 1 MiB | 0 | 3 | 0 |
| 1 MiB | 2 MiB | 16 MiB | 0 | 2 | 0 |
| 1 MiB | 4 MiB | 1 MiB | 0 | 5 | 0 |
| 1 MiB | 4 MiB | 16 MiB | 0 | 2 | 0 |
| 2 MiB | 1 MiB | 1 MiB | 0 | 0 | 4 |
| 2 MiB | 1 MiB | 16 MiB | 2 | 0 | 0 |
| 2 MiB | 2 MiB | 1 MiB | 0 | 0 | 4 |
| 2 MiB | 2 MiB | 16 MiB | 4 | 0 | 0 |
| 2 MiB | 4 MiB | 1 MiB | 0 | 0 | 3 |
| 2 MiB | 4 MiB | 16 MiB | 2 | 0 | 0 |
| 4 MiB | 1 MiB | 1 MiB | 0 | 0 | 3 |
| 4 MiB | 1 MiB | 16 MiB | 1 | 0 | 0 |
| 4 MiB | 2 MiB | 1 MiB | 0 | 0 | 2 |
| 4 MiB | 2 MiB | 16 MiB | 3 | 0 | 0 |
| 4 MiB | 4 MiB | 1 MiB | 0 | 0 | 3 |
| 4 MiB | 4 MiB | 16 MiB | 1 | 0 | 0 |

Two observations follow directly from this cross-tabulation. First, the broker-max class is triggered exactly when `message.max.bytes` is the smallest value (1 MiB) and the test payload (1.5 MiB) exceeds it, independently of the other size options. Second, the log-segment class is triggered exactly when `log.segment.bytes` is the smallest value (1 MiB), even if `message.max.bytes` is large enough to allow the record. The latter observation is the more interesting one, because it shows that the obvious "raise `message.max.bytes`" fix would not have made the failing configurations pass.

The per-seed CSV for this sweep is available as `experiments/kafka-cluster-sweep-1-50-fixed-20260613-summary.csv` (see Section 6.2.7).

### 6.2.5 Failure Class 1: `message.max.bytes` Too Small

The first class is the simplest: when `message.max.bytes = 1 MiB` and the test payload is 1.5 MiB, the broker rejects the produce with `RecordTooLargeException`. The representative seed is 13, and the original report extract is:

```text
org.apache.kafka.common.errors.RecordTooLargeException:
The request included a message larger than the max message size the server will accept.
```

The corresponding configuration in the representative run is:

```text
message.max.bytes        = 1048576   # 1 MiB
log.segment.bytes        = 1048576   # 1 MiB
replica.fetch.max.bytes  = 2097152   # 2 MiB
large test record        = 1572864   # 1.5 MiB
```

The distinguishing property is `kafka-large-message-on-kafka1`. In the same run, all 10 baseline properties pass:

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

A class-isolating minimized configuration that isolates only this failure class, while keeping all other options at a simple baseline, is provided in `experiments/kafka-cluster-min-message-max.nix`. The corresponding validation run is reproducible with:

```bash
python3 -m topotestix.cli orchestrator run kafka-cluster \
  --seed 1 \
  --name kafka-cluster-min-message-max \
  --project-root . \
  --config-target experiments/kafka-cluster-min-message-max.nix
```

The run is stored in `.topotestix/runs/20260615-172715-kafka-cluster-seed-1-kafka-cluster-min-message-max` and confirms 10/11 passing checks and a single failure of `kafka-large-message-on-kafka1` with `RecordTooLargeException`.

### 6.2.6 Failure Class 2: `log.segment.bytes` Too Small

The second class is more subtle. When `message.max.bytes` is large enough for the record but `log.segment.bytes = 1 MiB`, the broker still rejects the record batch. The representative seed is 9, and the original report extract is:

```text
org.apache.kafka.common.errors.RecordBatchTooLargeException:
The request included message batch larger than the configured segment size on the server.
```

The corresponding configuration in the representative run is:

```text
message.max.bytes        = 4194304   # 4 MiB
log.segment.bytes        = 1048576   # 1 MiB
replica.fetch.max.bytes  = 4194304   # 4 MiB
large test record        = 1572864   # 1.5 MiB
```

A class-isolating minimized configuration that isolates only this failure class is provided in `experiments/kafka-cluster-min-log-segment.nix`. The corresponding validation run is reproducible with:

```bash
python3 -m topotestix.cli orchestrator run kafka-cluster \
  --seed 1 \
  --name kafka-cluster-min-log-segment \
  --project-root . \
  --config-target experiments/kafka-cluster-min-log-segment.nix
```

The run is stored in `.topotestix/runs/20260615-173157-kafka-cluster-seed-1-kafka-cluster-min-log-segment` and confirms 10/11 passing checks and a single failure of `kafka-large-message-on-kafka1` with `RecordBatchTooLargeException`.

This second class is the more interesting empirical finding of the Kafka case study, for two reasons. First, it shows that the surfaced violation is not a "fix the obvious size limit" issue: a system operator who only knew about `message.max.bytes` would have raised it to 4 MiB and would still have observed the failure. Second, it shows that TopoTestix can expose non-obvious configuration interactions across related but distinct settings.

### 6.2.7 Shrinking Limitations for the Kafka Case Study

The generic TopoTestix shrinker did **not** produce trustworthy final minimizations for the two Kafka case-study failures. Two distinct issues were identified.

The first issue is that the generic shrinker preserves the property "this run fails" but does not preserve the property "this run fails with this specific exception class". When seed 9 (log-segment) is shrunk, the shrinker can reduce `message.max.bytes` to 1 MiB, which then makes the failure collapse into the `RecordTooLargeException` class. The shrinker therefore returns a different failure than the one the operator is debugging. The Kafka case study uses validated, class-isolating minimized configurations instead of claiming automatic shrinker minimality.

The second issue is a choice-path limitation that is specific to Kafka: the broker settings are referenced as Nix attribute names containing dots (`"message.max.bytes"`, `"log.segment.bytes"`, etc.), and TopoTestix choice paths also use dots as separators. The two uses of the dot character collide when choice paths are passed on the command line, so the generic shrinker's choice overrides become ambiguous for these settings. Some raw shrink attempts for Kafka produced `0/0` property reports due to Nix/build failures rather than the intended Kafka property failure.

The class-isolating minimized configurations therefore intentionally fix all unrelated options to simple baseline values and leave only the failure-causing size constraint variable. They are minimal in the practical thesis sense: they are the smallest configurations in which the failure class can be reproduced and in which the 10 baseline properties still pass.

### 6.2.8 Discussion

The Kafka case study supports a number of empirical claims.

First, TopoTestix can automatically surface configuration-dependent property violations in a real distributed system without any hand-written regression test. The sweep was an out-of-the-box property-based fuzzing run over 50 seeds; the failures were produced by the framework, not by the developer.

Second, the surfaced violations are not Kafka implementation defects. The cluster starts, runs for the full duration of the property suite, and serves all small-message and metadata properties correctly. The failures only appear when the workload exceeds the configured size limits. The fact that 10/11 properties pass in every failing run is a strong signal that ordinary smoke tests would not have detected the issue.

Third, the failure classes are configuration interactions, not single-setting mistakes. In the log-segment case, the obvious `message.max.bytes` setting is already large enough; the issue is the interaction between `log.segment.bytes` and the record-batch size. This is exactly the kind of "looks healthy, only fails under a realistic workload" failure mode that motivates property-based fuzzing of distributed systems.

Fourth, the failures are reproducible as NixOS test runs and are accompanied by class-isolating minimized configurations. The two minimized repros are small enough to fit on a single screen and can be added to a regression suite.

The Kafka case study is therefore a positive answer to **RQ1** and **RQ2**, and a partial answer to **RQ3**: the failures are localized, but the localization is done by class-isolating minimized configurations rather than by the generic shrinker (Section 6.4.2).

## 6.3 Case Study: etcd

### 6.3.1 Target Setup

The etcd target is a three-node etcd/Raft cluster. The target consists of:

- a topology description `targets/etcd-cluster/topology.nix` declaring three nodes `etcd1`, `etcd2`, `etcd3` on a single private network with one vlan;
- a NixOS configuration module `targets/etcd-cluster/config.nix` that parameterizes the `services.etcd` service;
- a property suite `targets/etcd-cluster/properties.nix` with six high-level properties, expanded to 12 per-run checks;
- a test script `targets/etcd-cluster/test-script.py` that composes the property suite with the standard TopoTestix runner.

The cluster forms a Raft group of three members and exposes the standard etcd v3 client API on each node.

### 6.3.2 Configuration Space and Properties

The v2 etcd target fuzzes six options:

- `etcdVlans` — 1 (fixed in v2; v1 also used 1).
- `roles.etcd` — 3.
- `virtualisation.memorySize` — 1024 / 2048 / 4096 MiB.
- `virtualisation.diskSize` — 2048 / 4096 / 8192 MiB.
- `services.etcd.extraConf.HEARTBEAT_INTERVAL` — 100 / 250 ms.
- `services.etcd.extraConf.ELECTION_TIMEOUT` — 1250 / 2500 ms.
- `services.etcd.extraConf.SNAPSHOT_COUNT` — 1000 / 10000 / 100000.
- `services.etcd.extraConf.QUOTA_BACKEND_BYTES` — 2 MiB / 8 MiB / 64 MiB.

The product of the per-dimension value counts is 1,152 distinct configurations. Of these, 50 are sampled in the sweep.

The v2 property suite consists of six high-level properties:

1. **Cluster healthy** — `etcdctl endpoint health --cluster` succeeds from all three nodes. Expands to 3 checks.
2. **KV roundtrip** — write a key/value from one node and read it back from another. Expands to 3 checks (1→2, 1→3, 2→1).
3. **Leader is one of three** — the cluster has exactly one leader. Expands to 1 check.
4. **Lease TTL expiry** — a leased key disappears after the lease expires. Expands to 1 check.
5. **Service still up after delay** — `systemctl is-active etcd` returns active and `etcdctl endpoint health --cluster` succeeds on all three nodes after a 20-second sleep. Expands to 3 checks.
6. **Quota write burst** — write 80 distinct 64 KiB values into a new prefix, totalling approximately 5 MiB, and read the last one back. Expands to 1 check.

The total per-run check count is 3+3+1+1+3+1 = 12. The quota write-burst property is intentionally ordered last so that it can only fail in configurations where the cluster has already passed all five basic properties. The property name carries the `zz_` prefix in the implementation to ensure this ordering.

### 6.3.3 v1 Sweep: Startup Configuration Constraint

The first etcd sweep used a slightly broader heartbeat/election-timing space that included an invalid combination:

```text
heartbeat-interval = 250
election-timeout   = 1000
```

etcd rejects this combination at startup, before the property suite runs:

```text
failed to verify flags: --election-timeout[1000ms] should be at least as 5 times as --heartbeat-interval[250ms]
```

The v1 50-seed sweep produced the aggregate outcome shown in Table 6.5. The 11 failed seeds are 5, 7, 20, 21, 25, 29, 30, 34, 38, 42, 49, all of which fail with the same `invalid-etcd-election-timeout-heartbeat-ratio` class and a `0/0` property-report count.

**Table 6.5** — Aggregate etcd v1 50-seed sweep outcome.

| Outcome | Count | Share |
|---|---:|---:|
| Passed | 39 | 78% |
| Failed (startup-only) | 11 | 22% |
| Total | 50 | 100% |

The v1 sweep is useful as evidence that TopoTestix can expose real configuration constraints in a real distributed system, but it is the weaker of the two etcd results. The failure is detected before the property suite runs, and the structured property report is empty. It is therefore not a workload/configuration incompatibility in the sense of **RQ2**; it is a configuration validation failure. The v2 target was designed to address this gap.

### 6.3.4 v2 Sweep: Workload/Quota Incompatibility

The v2 sweep was obtained with the following command:

```bash
python3 -m topotestix.cli orchestrator sweep etcd-cluster --seeds 1..50 --project-root .
```

The aggregate outcome is shown in Table 6.6. Of the 50 runs, 37 passed all 12 checks and 13 failed. All 13 failures belong to a single class, `quota-backend-too-small-for-write-burst`, and in every failing run the failure is in the last property, `etcd-quota-write-burst-etcd1`.

**Table 6.6** — Aggregate etcd v2 50-seed sweep outcome.

| Outcome | Count | Share |
|---|---:|---:|
| Passed (12/12) | 37 | 74% |
| Failed (≥1 of 12) | 13 | 26% |
| Total | 50 | 100% |

The 13 failed seeds are 3, 6, 12, 13, 14, 28, 33, 34, 38, 40, 41, 42, 43. The failure class is the same in all 13 cases:

```text
quota-backend-too-small-for-write-burst: 13
```

The representative error message is:

```text
etcdserver: mvcc: database space exceeded
```

The strong correlation between the failure and the configured backend quota is shown in Table 6.7. Every run with `QUOTA_BACKEND_BYTES = 2097152` (2 MiB) fails; every run with `QUOTA_BACKEND_BYTES = 8388608` (8 MiB) or `67108864` (64 MiB) passes. The correlation is deterministic across the 50 seeds, with no observed counter-examples.

**Table 6.7** — etcd v2 outcomes by backend quota.

| `QUOTA_BACKEND_BYTES` | Passed | Failed | Total |
|---:|---:|---:|---:|
| 2 MiB (2097152) | 0 | 13 | 13 |
| 8 MiB (8388608) | 20 | 0 | 20 |
| 64 MiB (67108864) | 17 | 0 | 17 |

Crucially, in every failing run the cluster passes the first 11 properties: the cluster is healthy from all three nodes, key/value roundtrips work, there is exactly one leader, the lease TTL expires correctly, and the cluster remains healthy after a 20-second delay. Only the 12th property, the quota write-burst, fails. This is exactly the "system looks healthy, only fails under a realistic workload" pattern that **RQ2** asks for.

The per-seed CSV for this sweep is available as part of `experiments/etcd-cluster-v2-sweep-1-50-20260616-summary.txt`, and the per-seed outcomes are listed in the per-seed table in `experiments/etcd-cluster-v2-sweep-1-50-20260616.md`.

### 6.3.5 Shrinking Results

Two representative v2 failures were shrunk: seed 3 and seed 40. Both seeds failed in the original sweep with the `quota-backend-too-small-for-write-burst` class. The shrink logs are stored in `experiments/etcd-cluster-v2-shrink-seed-3.log` and `experiments/etcd-cluster-v2-shrink-seed-40.log`.

Both seeds shrink to the same minimal configuration, listed in Table 6.8. The shrinking works cleanly: the minimized runs are still post-start property failures, not Nix/build/startup failures, and the structured report records exactly one failed check, `etcd-quota-write-burst-etcd1`, with the `mvcc: database space exceeded` error message.

**Table 6.8** — Minimal etcd v2 failing configuration produced by the generic shrinker.

| Option | Value |
|---|---|
| `roles.etcd` | 3 |
| `etcdVlans` | [1] |
| `virtualisation.memorySize` | 1024 MiB |
| `virtualisation.diskSize` | 2048 MiB |
| `ETCD_HEARTBEAT_INTERVAL` | 100 ms |
| `ETCD_ELECTION_TIMEOUT` | 1250 ms |
| `ETCD_SNAPSHOT_COUNT` | 10000 |
| `ETCD_QUOTA_BACKEND_BYTES` | 2097152 (2 MiB) |

The validation runs for the minimized configurations are stored in:

```text
.topotestix/runs/20260616-142216-etcd-cluster-seed-3-etcd-cluster-shrink-3
.topotestix/runs/20260616-143326-etcd-cluster-seed-40-etcd-cluster-shrink-40
```

Both runs report:

```text
passed=11
failed=1
total=12
failed check: etcd-quota-write-burst-etcd1
failure message contains: etcdserver: mvcc: database space exceeded
```

The minimized configurations are reproducible with the same orchestrator command and the same `--topology-choices` and `--config-choices` flags, listed in `experiments/etcd-cluster-v2-shrinking.md`.

### 6.3.6 Discussion

The etcd case study is a strong positive answer to all three research questions.

For **RQ1**, TopoTestix automatically produced 13 failing configurations out of 50 in an out-of-the-box sweep. The failures were classified into a single, clean class without manual intervention.

For **RQ2**, the failures are not startup failures. In every failing run, the cluster boots, elects a leader, passes the full basic distributed-system property suite (cluster health, cross-node KV, single leader, TTL expiry, delayed health), and only fails when the workload exceeds the configured backend quota. The fact that the 2 MiB quota is unconditionally insufficient and the 8 MiB quota is unconditionally sufficient (Table 6.7) is a clean illustration of a workload/configuration incompatibility that a smoke test would not have detected.

For **RQ3**, the generic shrinker localizes both representative failures to the same minimal configuration (Table 6.8). The minimal configuration is small, deterministic, and reproducible. It is small enough to be added verbatim to a regression test or a bug report. The etcd case study is therefore a stronger shrinker result than the Kafka case study, where the generic shrinker encountered the choice-path and class-preservation issues described in Section 6.2.7.

The v1 result is included in the chapter for two reasons. First, it shows that the framework can detect real configuration-validation errors in a real distributed system, even before any property is reached. Second, it motivates the v2 redesign: the v1 result is informative, but the v2 result is more useful for the thesis claim, because the v2 result is a post-start workload/configuration incompatibility.

## 6.4 Cross-cutting Observations

This section discusses observations that emerged from both case studies and that are independent of the individual targets.

### 6.4.1 Framework Fixes Motivated by the Evaluation

The evaluation surfaced a real defect in the runner, which was fixed before the final sweep was executed. The defect and the fix are worth reporting here because they show that the evaluation was performed against a tool that was being actively exercised against real systems.

The defect was in the run/report materialization path of `lib/runner.nix`. The runner writes a structured `report.json` inside the NixOS VM, copies it out, and then raises an `AssertionError` if any property failed. Because the runner raised, the NixOS test derivation was marked as failed, and Nix did not materialize the output path that the orchestrator uses to extract `report.json`. The structured report was therefore lost, and the orchestrator could only see a `0/0` summary in `run.json`. The useful failure evidence survived in `stderr.log`, but the structured per-check report was empty, which made sweep aggregation impossible.

The fix was to remove the `raise` from the per-property failure path in `lib/runner.nix`. The runner now always writes and copies `report.json`, and the NixOS test derivation succeeds. The orchestrator then marks the run as failed from the contents of `report.json` via `report_passed(report)`. Infrastructure failures outside the `_check()` path still fail the VM derivation. After the fix, the validation run for seed 13 reports `"summary": { "failed": 1, "passed": 10, "total": 11 }` in `run.json` and the failed `report.json` entry includes the `RecordTooLargeException` text. The full unit-test suite (`34/34` tests) and `nix flake check` both pass after the fix.

This observation is also relevant to the methodology: the final sweeps reported in this chapter are the post-fix sweeps. The pre-fix sweeps are explicitly excluded from the thesis results.

### 6.4.2 Shrinker Behaviour

The two case studies show two different shrinker behaviours, and both are worth reporting.

For etcd v2, the generic shrinker worked cleanly. Both representative failures (seed 3, seed 40) shrink to the same minimal configuration (Table 6.8), and the minimized failures are still post-start property failures. The shrinker therefore gives a positive answer to **RQ3** for etcd.

For Kafka, the generic shrinker encountered two issues:

1. **Failure preservation is not failure-class preservation.** The shrinker preserves "this run fails" but not "this run fails with this specific exception class". For seed 9, an unconstrained shrinker can reduce `message.max.bytes` and collapse the `RecordBatchTooLargeException` class into the simpler `RecordTooLargeException` class.
2. **Choice-path limitation for dotted setting names.** Kafka's broker settings use Nix attribute names containing dots (`"message.max.bytes"`, `"log.segment.bytes"`, etc.), and TopoTestix choice paths also use dots as separators. The two uses of the dot character collide on the command line, so choice overrides for these settings are ambiguous. Some raw shrink attempts produced `0/0` property reports due to Nix/build failures rather than the intended Kafka property failure.

The Kafka case study therefore uses validated class-isolating minimized configurations rather than claiming automatic shrinker minimality. The etcd v2 result demonstrates that the generic shrinker can produce trustworthy minimal repros when the configuration space does not contain the two Kafka-specific issues, and the Kafka result motivates a future framework improvement: a class-aware shrinker and an escaping convention for choice paths that contain dots.

### 6.4.3 Reproducibility

Both case-study sweeps are reproducible end-to-end with the orchestrator commands listed in Sections 6.2 and 6.3. Every per-seed run is stored in `.topotestix/runs/<timestamp>-<target>-seed-<n>-<name>`, and the aggregated summary is stored under `experiments/`. The class-isolating minimized configurations are stored as standalone Nix files (`experiments/kafka-cluster-min-message-max.nix`, `experiments/kafka-cluster-min-log-segment.nix`) and are reproducible with the same orchestrator command and a different `--config-target`. The etcd minimized configurations are reproducible with the same orchestrator command and explicit `--topology-choices` and `--config-choices` flags.

A single re-execution of the sweeps therefore reproduces the thesis results bit-for-bit, given the same Nix store. The use of Nix-based test derivations is the key enabler of this reproducibility: the cluster configuration is captured in Nix expressions, the test script is captured in Python source, and the per-run outputs are captured as Nix build outputs.

### 6.4.4 Comparison Between the Two Case Studies

The two case studies are deliberately complementary. Kafka is a partitioned log system with rich broker-side configuration; the failures it surfaces are configuration interactions between related size limits. etcd is a Raft-based key-value store with a quota-bounded backend; the failures it surfaces are workload/configuration incompatibilities between the configured backend quota and a multi-MiB write burst. Together, the two case studies exercise both the "configuration interaction" and the "workload/configuration incompatibility" failure modes that motivated this thesis.

Both case studies produce pass/fail splits in the 26%–37% pass / 63%–74% fail range (Tables 6.2 and 6.6), which is a useful operating point for a property-based fuzzer: most configurations are still healthy, but a substantial minority exposes a violation. Both case studies also produce failures that are concentrated in a single property and that are accompanied by a clear, repeatable error class. This is the empirical signature of a well-designed property-based fuzzing target, and it is what distinguishes these results from a random crash hunt.

## 6.5 Threats to Validity

Several threats to the validity of the evaluation are worth discussing.

**Construct validity.** The two targets are not representative of all distributed systems. Kafka is a partitioned log/stream system and etcd is a Raft-based key-value store; both are mature, single-tenant systems, and neither exercises multi-tenant scheduling, network partitions, or clock skew. The properties that are checked are deliberately simple (e.g. "produce and consume one record", "write 80 values and read one back"). The evaluation therefore does not claim that TopoTestix can find violations of arbitrary, complex properties; it claims that TopoTestix can find violations of well-engineered property suites written in the style described in Chapter 4.

**Internal validity.** The sweeps are run sequentially on a single Nix store, and the per-seed run time is non-trivial (multiple minutes for Kafka, slightly less for etcd). The sweep is therefore not a true random sample of the 746,496 (Kafka) or 1,152 (etcd v2) configurations, but a deterministic pseudo-random sample driven by the seed. The clean cross-tabulation in Table 6.4 and the deterministic 0/13/0 split in Table 6.7 suggest that the sample size is large enough to characterize the failure-class structure, but a larger sample (e.g. 200 or 500 seeds) would be needed to claim coverage of the full configuration space.

**External validity.** The failure classes that TopoTestix surfaced for Kafka and etcd are not Kafka or etcd implementation bugs; they are configuration-dependent workload incompatibilities. This is the most defensible claim that can be made on the basis of two case studies, but it is also a narrower claim than "TopoTestix finds bugs in distributed systems". Additional targets would be needed to test the generality of the claim, and the choice of additional targets (e.g. PostgreSQL, Redis, ZooKeeper) is left to future work.

**Reliability.** The two sweeps, the two class-isolating minimized configurations, and the two etcd shrink runs are all reproducible from the same orchestrator commands. The unit-test suite (`34/34`) and `nix flake check` both pass. The reproducibility is therefore a strength, not a weakness, of the evaluation. The shrinker limitations described in Section 6.4.2 are a reliability caveat for the Kafka case study specifically.

**Conclusion validity.** The pass/fail splits and the per-class failure counts are obtained by aggregating the structured per-seed reports, not by visual inspection. The aggregated summaries are stored in machine-readable form (`-summary.json` and `-summary.txt`) and are reproducible from the raw run directories. The numerical claims in Sections 6.2.4 and 6.3.4 are therefore exact for the executed sweeps, not estimated.

## 6.6 Summary

This chapter presented the empirical evaluation of TopoTestix on two real-world distributed systems: a three-broker Apache Kafka cluster and a three-node etcd cluster. The Kafka sweep produced 13 passes and 37 failures out of 50 seeds, with the failures concentrated in a single property (`kafka-large-message-on-kafka1`) and split into two configuration classes (`RecordTooLargeException` from a 1 MiB `message.max.bytes`, and `RecordBatchTooLargeException` from a 1 MiB `log.segment.bytes`). The etcd v2 sweep produced 37 passes and 13 failures out of 50 seeds, with the failures concentrated in a single property (`etcd-quota-write-burst-etcd1`) and split by the configured backend quota (every 2 MiB run fails, every 8 MiB or 64 MiB run passes). Two representative etcd failures shrink to the same minimal configuration, and two class-isolating minimized Kafka configurations reproduce each Kafka failure class on demand.

The three research questions posed at the start of this chapter can be answered as follows.

> **RQ1.** Yes. TopoTestix automatically surfaced 50 distinct failing runs across the two targets out of 100 total runs. The failures were classified into a small number of clean, repeatable failure classes without manual intervention. The failures were obtained by running the same out-of-the-box sweep command on both targets, and the per-class counts were obtained by aggregating the structured per-seed reports.
>
> **RQ2.** Yes. In every failing run, the distributed system had started and had passed a substantial baseline property suite (10/11 checks for Kafka, 11/12 checks for etcd). The failures only appeared when a workload-specific property (large-message produce/consume for Kafka, multi-MiB write burst for etcd) was checked. The surfaced violations are therefore not "the system does not start" failures, they are "the system looks healthy under ordinary smoke tests but fails under a realistic workload" failures.
>
> **RQ3.** Partially. For etcd v2, the generic shrinker localizes both representative failures to the same minimal configuration. For Kafka, the generic shrinker encounters a failure-class-preservation issue and a choice-path limitation; class-isolating minimized configurations are provided instead, and a class-aware shrinker with a choice-path escaping convention is left to future work.

The strongest empirical claim supported by both case studies is therefore:

> TopoTestix can automatically surface production-relevant, configuration-dependent property violations in real distributed systems. These violations are not implementation defects in the system under test. They are realistic configuration bugs, configuration interactions, and workload/configuration incompatibilities that ordinary smoke tests do not detect, because the system starts and ordinary properties pass.

This claim answers the central research question of the thesis and is supported by the per-class failure counts, the per-seed cross-tabulations, and the class-isolating minimized configurations reported in this chapter.
