# PostgreSQL v1 sweep readiness

Target: `postgresql`

## Purpose

This target is intended as a green v1 PostgreSQL SUT for a first empirical sweep. It boots a two-node physical streaming-replication cluster:

```text
primary1 -> standby1
```

Bootstrap uses PostgreSQL 12+ recovery semantics:

```text
pg_basebackup -R
standby.signal
postgresql.auto.conf primary_conninfo
```

The pinned nixpkgs package used by the target is PostgreSQL 17.9 (`pkgs.postgresql_17`). No nixpkgs pin change is required.

## v1 scope

Included:

- one primary,
- one physical standby,
- trust authentication inside the isolated VM test network,
- streaming replication,
- smoke write replicated from primary to standby,
- v1 property suite.

Excluded from v1:

- failover,
- archiving,
- cascading replication,
- logical replication,
- synchronous replication assertions,
- intentional failure injection.

## v1 fuzz surface

The fixed v1 fuzz surface has 9 knobs:

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

The following hot-standby-sensitive GUCs are intentionally **not fuzzed** because PostgreSQL requires the standby value to be at least the primary value, while TopoTestix currently fuzzes per role independently:

```text
max_connections
max_wal_senders
max_worker_processes
max_prepared_transactions
max_locks_per_transaction
```

During bring-up, `max_connections` and `max_wal_senders` were tried and removed because they produced expected standby startup failures when the standby value was lower than the primary.

## v1 properties

The suite checks:

- primary is not in recovery,
- standby is in recovery,
- `standby.signal` exists,
- primary sees one streaming standby,
- standby WAL receiver is streaming,
- primary write replicates to standby,
- standby is read-only,
- both services remain up after a delay.

## Validation before 50-seed sweep

Completed fresh validation:

```text
seed 1 smoke: passed
sweep 1..3: passed
sweep 1..10: passed
```

Preflight for seeds `1..50` confirmed that none of the known hot-standby-sensitive GUCs are fuzzed.

## First 50-seed command

Run fresh, without `--resume`, after any target/property changes:

```bash
nix-shell -p python3 python3Packages.textual --run \
  "python3 -m topotestix.cli orchestrator sweep postgresql --seeds 1..50 --project-root . --json"
```
