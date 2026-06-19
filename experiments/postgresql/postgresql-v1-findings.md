# PostgreSQL v1 findings

Target: `postgresql`

Date: 2026-06-18

## Summary

TopoTestix did **not** find a PostgreSQL implementation bug in the final v1 experiment. The final compatibility-preserving v1 surface passed 50/50 seeds.

During bring-up, however, TopoTestix did expose a real PostgreSQL primary/standby configuration compatibility constraint:

> Some hot-standby-sensitive PostgreSQL settings are cluster-coupled. A physical standby cannot start recovery if its value is lower than the primary value.

This is expected PostgreSQL behavior, but it is a useful empirical finding for the thesis because it shows that independently fuzzing per-node settings in a distributed deployment can synthesize invalid distributed configurations.

## Constraint found

The incompatible pattern is:

```text
primary1: setting = higher value
standby1: setting = lower value
```

For physical streaming replication, PostgreSQL rejects the standby during recovery for settings that must be at least as high on the standby as on the primary.

The concrete parameters observed during bring-up were:

```text
max_connections
max_wal_senders
```

Related hot-standby-sensitive parameters intentionally kept out of the final v1 fuzz surface are:

```text
max_connections
max_wal_senders
max_worker_processes
max_prepared_transactions
max_locks_per_transaction
```

## Evidence: `max_connections`

An early sweep included `max_connections` in the fuzz surface. Seed 2 produced:

```text
primary1: max_connections = 100
standby1: max_connections = 50
```

Run directory:

```text
.topotestix/runs/20260616-195810-postgresql-seed-2-postgresql-seed-2
```

Relevant log excerpt from `stderr.log`:

```text
standby1 # postgres[...] FATAL:  recovery aborted because of insufficient parameter settings
standby1 # postgres[...] DETAIL:  max_connections = 50 is a lower setting than on the primary server, where its value was 100.
standby1 # postgres[...] HINT:  You can restart the server after making the necessary configuration changes.
```

The NixOS VM test then failed while waiting for the PostgreSQL unit:

```text
RequestedAssertionFailed: unit "postgresql" reached state "failed"
```

This was a startup/recovery-time VM failure before TopoTestix properties ran. The run summary was therefore `0/0` properties, not a property failure.

## Evidence: `max_wal_senders`

After removing `max_connections`, the next unsafe cross-role parameter was `max_wal_senders`. Seeds 4 and 8 produced:

```text
primary1: max_wal_senders = 10
standby1: max_wal_senders = 5
```

Run directories:

```text
.topotestix/runs/20260616-200513-postgresql-seed-4-postgresql-seed-4
.topotestix/runs/20260616-200951-postgresql-seed-8-postgresql-seed-8
```

Representative log excerpt from `stderr.log`:

```text
standby1 # postgres[...] FATAL:  recovery aborted because of insufficient parameter settings
standby1 # postgres[...] DETAIL:  max_wal_senders = 5 is a lower setting than on the primary server, where its value was 10.
standby1 # postgres[...] HINT:  You can restart the server after making the necessary configuration changes.
```

The VM test again failed before properties ran:

```text
RequestedAssertionFailed: unit "postgresql" reached state "failed"
```

## Why the final 50-seed sweep passed

The final v1 fuzz surface removed independently fuzzed hot-standby-sensitive settings and kept only compatibility-preserving knobs:

```text
virtualisation.memorySize
virtualisation.diskSize
services.postgresql.settings.checkpoint_timeout
services.postgresql.settings.shared_buffers
services.postgresql.settings.work_mem
services.postgresql.settings.maintenance_work_mem
services.postgresql.settings.wal_keep_size
services.postgresql.settings.checkpoint_completion_target
services.postgresql.settings.max_wal_size
```

With that surface, seeds `1..50` passed:

```json
{
  "completed": 50,
  "failed": 0,
  "failures": [],
  "skipped": 0,
  "target": "postgresql",
  "total": 50
}
```

Raw result log:

```text
experiments/postgresql/postgresql-sweep-1-50-v1-20260618-175119.log
```

Summary:

```text
experiments/postgresql/postgresql-sweep-1-50-v1-20260618.md
```

## Thesis framing

Use this framing:

> TopoTestix did not find a PostgreSQL implementation bug in the final v1 sweep. It did expose a real configuration compatibility constraint: in a physical streaming-replication deployment, some settings are not safely node-local. If TopoTestix fuzzes those values independently per role, it can generate invalid primary/standby configurations that PostgreSQL rejects during standby recovery.

Avoid claiming this is a PostgreSQL bug. The behavior is PostgreSQL enforcing documented/expected recovery invariants. The useful result is that TopoTestix surfaced a distributed configuration invariant that the target generator must respect.
