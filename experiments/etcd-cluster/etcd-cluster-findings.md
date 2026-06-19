# etcd-cluster findings

## v1 sweep: seeds 1..50

Artifacts:

```text
experiments/etcd-cluster-sweep-1-50-20260615.log
experiments/etcd-cluster-sweep-38-50-20260616.log
experiments/etcd-cluster-sweep-1-50-20260616.md
experiments/etcd-cluster-sweep-1-50-20260616-summary.json
experiments/etcd-cluster-sweep-1-50-20260616-summary.txt
```

The first foreground command hit the 3-hour harness timeout after seed 37. Seeds 38..50 were completed in a continuation run. The summary was reconstructed from the latest `run.json` for each seed after the sweep began.

Aggregate result:

| Outcome | Count |
|---|---:|
| Passed | 39 |
| Failed | 11 |
| Total | 50 |

Failed seeds:

```text
5, 7, 20, 21, 25, 29, 30, 34, 38, 42, 49
```

All 11 failures had the same class:

```text
invalid-etcd-election-timeout-heartbeat-ratio
```

Representative etcd log message:

```text
failed to verify flags: --election-timeout[1000ms] should be at least as 5 times as --heartbeat-interval[250ms]
```

## Interpretation

This is a real etcd configuration constraint, not an etcd implementation bug.

However, it is a **startup-only** failure. etcd rejects the configuration before the TopoTestix property suite runs, so the failing runs have `0/0` property reports. This is useful evidence that TopoTestix can expose invalid real-world configuration combinations, but it is weaker than Kafka's data-plane failures for the thesis empirical chapter.

## v2 plan

For `etcd-cluster` v2, the target should avoid the invalid startup-only timing combination and instead look for post-start/runtime failures.

Changes:

1. Keep heartbeat/election combinations valid:
   - `HEARTBEAT_INTERVAL = 100 or 250`
   - `ELECTION_TIMEOUT = 1250 or 2500`
   - Both election values are at least `5 * 250`, so all cross-products satisfy etcd's startup validation.
2. Add smaller backend quota variants:
   - `QUOTA_BACKEND_BYTES = 2 MiB, 8 MiB, 64 MiB`
3. Add a quota-stress property that writes several MiB of values after all basic health/leader/KV/TTL checks have passed.

Expected v2 failure mode:

```text
etcd starts and basic cluster properties pass, but quota-stress writes fail under a small backend quota with a database-space-exceeded error.
```

This is thesis-useful as a production-relevant workload/configuration incompatibility, analogous to the Kafka large-message case but for a Raft key-value store.

## v2 sweep: seeds 1..50

Artifacts:

```text
experiments/etcd-cluster-v2-sweep-1-25-20260616.log
experiments/etcd-cluster-v2-sweep-26-50-20260616.log
experiments/etcd-cluster-v2-sweep-1-50-20260616.md
experiments/etcd-cluster-v2-sweep-1-50-20260616-summary.json
experiments/etcd-cluster-v2-sweep-1-50-20260616-summary.txt
```

Aggregate result:

| Outcome | Count |
|---|---:|
| Passed | 37 |
| Failed | 13 |
| Total | 50 |

Failed seeds:

```text
3, 6, 12, 13, 14, 28, 33, 34, 38, 40, 41, 42, 43
```

Failure class:

```text
quota-backend-too-small-for-write-burst: 13
```

Quota correlation:

| quota-backend-bytes | Passed | Failed |
|---:|---:|---:|
| 2097152 | 0 | 13 |
| 8388608 | 20 | 0 |
| 67108864 | 17 | 0 |

Representative error:

```text
etcdserver: mvcc: database space exceeded
```

Representative seed: `3`.

Representative run:

```text
.topotestix/runs/20260616-075438-etcd-cluster-seed-3-etcd-cluster-seed-3
```

Shrinking results:

```text
experiments/etcd-cluster-v2-shrinking.md
experiments/etcd-cluster-v2-shrink-seed-3.log
experiments/etcd-cluster-v2-shrink-seed-40.log
```

Both seed 3 and seed 40 shrink to the same minimal choices: 3 etcd nodes, 1 GiB memory, 2 GiB disk, valid low timing values, and `QUOTA_BACKEND_BYTES = 2097152`.

In the representative failure, etcd starts and the first 11 checks pass:

- cluster health from all three nodes,
- cross-node KV roundtrips,
- exactly one leader,
- TTL expiry,
- delayed health checks.

Only the final quota write-burst property fails. This is the stronger etcd result for the thesis because it is a post-start workload/configuration incompatibility rather than a startup validation failure.

Thesis-safe wording:

> The etcd v2 experiment did not reveal an etcd implementation defect. It showed that TopoTestix can surface a production-relevant workload/configuration incompatibility in a real Raft-based key-value store: a cluster configured with a small backend quota starts and passes basic distributed-system checks, but fails under a multi-MiB write burst with `mvcc: database space exceeded`.
