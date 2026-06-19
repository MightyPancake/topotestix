# etcd-cluster target notes

`etcd-cluster` is a three-node etcd/Raft target added as the second real distributed SUT after Kafka.

## Target files

```text
targets/etcd-cluster/topology.nix
targets/etcd-cluster/config.nix
targets/etcd-cluster/module.nix
targets/etcd-cluster/test-script.py
targets/etcd-cluster/properties.nix
targets/default.nix
```

## Topology

- 3 etcd nodes: `etcd1`, `etcd2`, `etcd3`
- fully connected on VLAN 1
- ports:
  - `2379` client traffic
  - `2380` peer traffic

## Fuzzed configuration dimensions

```text
virtualisation.memorySize: 1024, 2048
virtualisation.diskSize: 2048, 4096
ETCD_HEARTBEAT_INTERVAL: 100, 250
ETCD_ELECTION_TIMEOUT: 1000, 2500
ETCD_SNAPSHOT_COUNT: 10000, 100000
ETCD_QUOTA_BACKEND_BYTES: 16777216, 67108864
```

The NixOS etcd module in this nixpkgs revision does not expose a generic `services.etcd.settings` option, so etcd-specific fuzzing is implemented via `services.etcd.extraConf`, which maps to `ETCD_*` environment variables.

## Properties

The current target checks 11 property outcomes per run:

- cluster health from all three nodes,
- KV roundtrips across nodes,
- exactly one Raft leader,
- lease/TTL expiry,
- service health after a delay from all three nodes.

## Smoke validation

Fresh fixed 1..3 smoke sweep:

```text
experiments/etcd-cluster-smoke-1-3-fixed.log
```

Result:

```json
{
  "completed": 3,
  "failed": 0,
  "failures": [],
  "skipped": 0,
  "target": "etcd-cluster",
  "total": 3
}
```

Initial TTL property issue:

- The first TTL property used a fixed key and a short fixed wait.
- Seeds 2 and 3 exposed that as too brittle.
- The property now uses a unique key and polls for expiry for up to 10 seconds.
- Seeds 1, 2, and 3 pass after that fix.

## 50-seed sweep

Completed artifacts:

```text
experiments/etcd-cluster-sweep-1-50-20260615.log
experiments/etcd-cluster-sweep-38-50-20260616.log
experiments/etcd-cluster-sweep-1-50-20260616-summary.json
experiments/etcd-cluster-sweep-1-50-20260616-summary.txt
experiments/etcd-cluster-sweep-1-50-20260616.md
```

The first foreground command hit the 3-hour harness timeout after seed 37, so seeds 38..50 were completed in a continuation command. The summary files were reconstructed from the latest `run.json` for each seed after the sweep began.

Result:

```text
passed=39 failed=11 total=50
```

Failed seeds:

```text
5, 7, 20, 21, 25, 29, 30, 34, 38, 42, 49
```

All 11 failures are the same etcd startup/configuration class:

```text
election-timeout=1000 with heartbeat-interval=250
```

etcd rejects this because election timeout must be at least five times heartbeat interval:

```text
failed to verify flags: --election-timeout[1000ms] should be at least as 5 times as --heartbeat-interval[250ms]
```

Interpretation: this is a real etcd configuration constraint, not an etcd implementation bug. It is also a startup-only failure (`0/0` properties), so it is weaker than a runtime/data-plane case study.

## v2 50-seed sweep

v2 removes the invalid timing combination and adds a quota write-burst property.

Completed artifacts:

```text
experiments/etcd-cluster-v2-sweep-1-25-20260616.log
experiments/etcd-cluster-v2-sweep-26-50-20260616.log
experiments/etcd-cluster-v2-sweep-1-50-20260616.md
experiments/etcd-cluster-v2-sweep-1-50-20260616-summary.json
experiments/etcd-cluster-v2-sweep-1-50-20260616-summary.txt
```

Result:

```text
passed=37 failed=13 total=50
```

All 13 failures are post-start property failures:

```text
quota-backend-too-small-for-write-burst
```

The failure appears exactly when `QUOTA_BACKEND_BYTES = 2097152`; the 8 MiB and 64 MiB quota variants passed.

This v2 result is the recommended etcd thesis case-study result.
