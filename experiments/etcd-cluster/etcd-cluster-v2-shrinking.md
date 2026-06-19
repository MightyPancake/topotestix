# etcd-cluster v2 shrinking results

## Failure class

All v2 sweep failures belong to one class:

```text
quota-backend-too-small-for-write-burst
```

The final property writes a multi-MiB burst into etcd. With a 2 MiB backend quota, etcd starts and passes all basic distributed-system checks, but the burst eventually fails with:

```text
etcdserver: mvcc: database space exceeded
```

## Shrunk seeds

Two representative seeds were shrunk:

| Seed | Original class | Shrink result |
|---:|---|---|
| 3 | quota write burst exceeds 2 MiB backend quota | same class, minimal choices |
| 40 | quota write burst exceeds 2 MiB backend quota | same class, same minimal choices |

Shrink logs:

```text
experiments/etcd-cluster-v2-shrink-seed-3.log
experiments/etcd-cluster-v2-shrink-seed-40.log
```

Final validated run directories:

```text
.topotestix/runs/20260616-142216-etcd-cluster-seed-3-etcd-cluster-shrink-3
.topotestix/runs/20260616-143326-etcd-cluster-seed-40-etcd-cluster-shrink-40
```

Both final reports show:

```text
passed=11
failed=1
total=12
failed check: etcd-quota-write-burst-etcd1
failure message contains: etcdserver: mvcc: database space exceeded
```

## Minimal choices

Both shrunk seeds converge to the same choice map.

Topology:

```json
{
  ".etcdVlans": 0,
  ".roles.etcd": 0
}
```

Config:

```json
{
  "etcd": {
    ".services.etcd.extraConf.ELECTION_TIMEOUT": 0,
    ".services.etcd.extraConf.HEARTBEAT_INTERVAL": 0,
    ".services.etcd.extraConf.QUOTA_BACKEND_BYTES": 0,
    ".services.etcd.extraConf.SNAPSHOT_COUNT": 0,
    ".virtualisation.diskSize": 0,
    ".virtualisation.memorySize": 0
  }
}
```

Resolved minimal configuration:

```text
roles.etcd = 3
etcdVlans = [ 1 ]
virtualisation.memorySize = 1024
virtualisation.diskSize = 2048
ETCD_HEARTBEAT_INTERVAL = 100
ETCD_ELECTION_TIMEOUT = 1250
ETCD_SNAPSHOT_COUNT = 10000
ETCD_QUOTA_BACKEND_BYTES = 2097152
```

Important: unlike the Kafka case, the generic shrinker worked cleanly here. The minimized failure is still a property-level failure after etcd starts, not a Nix/build/startup failure.

## Reproduce seed 3 minimized failure

```bash
python3 -m topotestix.cli orchestrator run etcd-cluster \
  --seed 3 \
  --name etcd-cluster-shrink-3 \
  --project-root . \
  --topology-choices '{".etcdVlans": 0, ".roles.etcd": 0}' \
  --config-choices '{"etcd": {".services.etcd.extraConf.ELECTION_TIMEOUT": 0, ".services.etcd.extraConf.HEARTBEAT_INTERVAL": 0, ".services.etcd.extraConf.QUOTA_BACKEND_BYTES": 0, ".services.etcd.extraConf.SNAPSHOT_COUNT": 0, ".virtualisation.diskSize": 0, ".virtualisation.memorySize": 0}}'
```

## Reproduce seed 40 minimized failure

```bash
python3 -m topotestix.cli orchestrator run etcd-cluster \
  --seed 40 \
  --name etcd-cluster-shrink-40 \
  --project-root . \
  --topology-choices '{".etcdVlans": 0, ".roles.etcd": 0}' \
  --config-choices '{"etcd": {".services.etcd.extraConf.ELECTION_TIMEOUT": 0, ".services.etcd.extraConf.HEARTBEAT_INTERVAL": 0, ".services.etcd.extraConf.QUOTA_BACKEND_BYTES": 0, ".services.etcd.extraConf.SNAPSHOT_COUNT": 0, ".virtualisation.diskSize": 0, ".virtualisation.memorySize": 0}}'
```

## Thesis interpretation

The minimized etcd v2 failure is a strong empirical case:

> A three-node etcd cluster starts, elects one leader, passes health checks, supports cross-node key/value reads, honors TTL expiry, and remains healthy after a delay. Only when TopoTestix applies a larger write-burst workload does the small backend quota become visible as `mvcc: database space exceeded`.

This should be framed as a production-relevant workload/configuration incompatibility, not an etcd implementation bug.
