# TopoTestix — Test-case plan (next phase)

## Context

The framework is functionally complete: `docs/plan.md` Phases 1–6 are all checked, `nix flake check` is green, the `topotestix` CLI runs end-to-end, and two passing nginx runs sit in `.topotestix/runs/`. The only gap is empirical — there is no Kafka data, no multi-node data, no failure to shrink, no case study to put in the thesis.

This plan covers the next phase of work: **build a diverse, bug-rich SUT portfolio and run real sweeps against it, so the master's thesis has an empirical-evaluation chapter grounded in real findings on real software.**

## SUT portfolio

Four SUTs, ordered by thesis importance:

| SUT | Nodes | System type | Thesis role | Status |
|---|---|---|---|---|
| **kafka-cluster** | 3 | Log-based messaging (KRaft) | Headline: replication, partition tolerance | Expand (see below) |
| **etcd** | 3 | Strongly-consistent KV (Raft) | Compare against Kafka on consensus + partition behavior | New |
| **postgresql** | 2 | Relational DB w/ streaming replication | Async replication, write durability | New |
| **nginx** | 1 | HTTP server | Smoke target only; **drop from thesis chapter** | Unchanged |

**Why these three multi-node SUTs.** Kafka is the headline because it is the SUT originally advertised in `docs/idea.md`, but Kafka is heavily production-tested and the current `kafka-cluster` target has a very small fuzzable surface (4 options, 1 property). To maximize the chance of finding a *real* config-induced failure we pair it with:

- **etcd** — Raft consensus, well-known to be sensitive to network partitions and timing; the literature is rich enough to cite in the thesis.
- **PostgreSQL with streaming replication** — async replication, a different consistency model; classic failure modes (replica lag, divergence, failover).

That spans the three property categories in `docs/idea.md` (connectivity, availability, fault tolerance) across two consensus models and one async-replication model.

NixOS support is mature for all three (`services.etcd`, `services.postgresql`, `services.apache-kafka` are all first-class modules in nixpkgs), so we are not betting on experimental infrastructure.

## Phase 1 — Strengthen `kafka-cluster`

### 1.1 Expand `targets/config/kafka-cluster.nix`

Replace the current 4-option spec with this larger one. The new options interact with each other and with the 3-node topology in ways that have known failure modes in production.

```nix
{ lib, ... }:

{
  # Resources (low values surface OOM and slow-start failures)
  virtualisation.memorySize = [ 1536 2048 3072 4096 ];
  virtualisation.diskSize    = [ 2048 4096 8192 ];

  # JVM heap — extreme variant is intentionally OOM-prone
  services.apache-kafka.jvmOptions = [
    [ "-Xms64m"  "-Xmx128m" ]
    [ "-Xms256m" "-Xmx512m" ]
    [ "-Xms512m" "-Xmx768m" ]
  ];

  # Cluster-level tunables that interact with the 3-node topology
  services.apache-kafka.settings."offsets.topic.replication.factor"         = [ 1 3 ];
  services.apache-kafka.settings."transaction.state.log.replication.factor" = [ 1 3 ];
  services.apache-kafka.settings."transaction.state.log.min.isr"             = [ 1 2 ];
  services.apache-kafka.settings."min.insync.replicas"                      = [ 1 2 ];
  services.apache-kafka.settings."default.replication.factor"               = [ 1 3 ];

  # Behavior knobs with known fragility
  services.apache-kafka.settings."unclean.leader.election.enable" = [ false true ];
  services.apache-kafka.settings."auto.create.topics.enable"       = [ false true ];
  services.apache-kafka.settings."log.retention.hours"             = [ 1 24 168 ];
  services.apache-kafka.settings."log.segment.bytes"               = [ 1048576 16777216 ];

  # Threading (already there, keep)
  services.apache-kafka.settings."num.network.threads" = [ 2 3 ];
  services.apache-kafka.settings."num.io.threads"      = [ 4 6 ];
}
```

### 1.2 Expand `targets/kafka-cluster/properties.nix`

Keep the existing `topic_visible_from_all_brokers`, add these:

- **`topic_roundtrip`** — produce a known payload on one broker, consume it back from the same broker, assert exact match. Tests the data plane, not just the control plane.
- **`service_still_up_after_delay`** — sleep 30 s, then assert `systemctl is-active apache-kafka` on all three brokers. Surfaces JVM-OOM and slow-start failures.
- **`multi_topic_creation`** — create three topics with `--partitions 3 --replication-factor 3`, then list them and assert all three appear. Surfaces replication-factor-vs-cluster-size mismatches.

```nix
{ lib }:

{
  topic_visible_from_all_brokers = { /* unchanged */ };

  topic_roundtrip = {
    name = "kafka-topic-roundtrip";
    setup = ''
      def _roundtrip(machine):
          machine.succeed(
              "echo 'topotestix-payload' | "
              "kafka-console-producer.sh --bootstrap-server localhost:9092 "
              "--topic topotestix-cluster 2>/dev/null"
          )
          machine.succeed(
              "kafka-console-consumer.sh --bootstrap-server localhost:9092 "
              "--topic topotestix-cluster --from-beginning --max-messages 1 "
              "--timeout-ms 10000 2>/dev/null | grep '^topotestix-payload$'"
          )
    '';
    check = ''
      _check("kafka-roundtrip-on-kafka1", _roundtrip, kafka1)
      _check("kafka-roundtrip-on-kafka2", _roundtrip, kafka2)
      _check("kafka-roundtrip-on-kafka3", _roundtrip, kafka3)
    '';
  };

  service_still_up_after_delay = {
    name = "kafka-still-up-after-delay";
    setup = ''
      def _still_up(machine):
          machine.succeed("sleep 30 && systemctl is-active apache-kafka")
    '';
    check = ''
      _check("kafka-still-up-kafka1", _still_up, kafka1)
      _check("kafka-still-up-kafka2", _still_up, kafka2)
      _check("kafka-still-up-kafka3", _still_up, kafka3)
    '';
  };

  multi_topic_creation = {
    name = "kafka-multi-topic-creation";
    setup = ''
      def _multi_topic(machine):
          for t in topotestix-a topotestix-b topotestix-c:
              machine.succeed(
                  f"kafka-topics.sh --bootstrap-server localhost:9092 "
                  f"--create --if-not-exists --topic {t} "
                  f"--partitions 3 --replication-factor 3"
              )
          machine.succeed(
              "kafka-topics.sh --bootstrap-server localhost:9092 --list | "
              "grep -E '^(topotestix-a|topotestix-b|topotestix-c)$' | wc -l | grep '^3$'"
          )
    '';
    check = ''
      _check("kafka-multi-topic-on-kafka1", _multi_topic, kafka1)
    '';
  };
}
```

### 1.3 Verify before scaling

```
nix flake check
python3 -m topotestix.cli orchestrator run kafka-cluster --seed 1 --project-root .
python3 -m topotestix.cli orchestrator run kafka-cluster --seed 2 --project-root .
```

If either build fails, fix the module/property before doing the 50-seed sweep. The first kafka-cluster build is the long pole (~5–10 min) — every subsequent run reuses the cache.

## Phase 2 — New SUT: `etcd-cluster` (3-node Raft)

### 2.1 `targets/topology/etcd-cluster.nix`

```nix
{ lib, ... }:

{
  roles.etcd = [ 3 ];
  # Two scenarios: fully shared (VLAN 1 only) vs. shared + extra hop (VLAN 1 + 10).
  # The fuzzer picks one; the second is a soft partition / extra-latency scenario.
  etcdVlans = [ [ 1 ] [ 1 10 ] ];
}
```

### 2.2 `targets/config/etcd.nix`

```nix
{ lib, ... }:

{
  virtualisation.memorySize = [ 512 1024 2048 ];

  # Booleans ordered false→true (false is simpler, per shrinking convention)
  services.etcd.enable = [ false true ];

  # Logging verbosity — high verbosity on tiny VMs is a known disk-pressure source
  services.etcd.settings."log-level" = [ "warn" "info" "debug" ];
}
```

### 2.3 `targets/etcd-cluster/module.nix`

`{ pkgs, nodeName, ... }: { ... }` — derives node id from a name→id map, builds `initialCluster` from the static set `{ etcd1, etcd2, etcd3 }`, exposes 2379 (client) and 2380 (peer), and adds `etcdctl` to `environment.systemPackages`.

### 2.4 `targets/etcd-cluster/test-script.py`

```python
start_all()
for m in [etcd1, etcd2, etcd3]:
    m.wait_for_unit("etcd")
    m.wait_for_open_port(2379)
    m.wait_for_open_port(2380)
etcd1.succeed("etcdctl endpoint health --cluster")
etcd1.succeed("etcdctl put topotestix-key topotestix-value")
etcd2.succeed("etcdctl get topotestix-key | grep '^topotestix-value$'")
```

### 2.5 `targets/etcd-cluster/properties.nix`

- `cluster_healthy` — `etcdctl endpoint health --cluster` reports all three endpoints healthy.
- `kv_roundtrip` — put on `etcd1`, get on `etcd2` and `etcd3`, value matches.
- `leader_is_one_of_three` — `etcdctl endpoint status --cluster -w json` reports exactly 1 leader and 2 followers (not 3 leaders, not 0).
- `service_still_up_after_delay` — sleep 30 s, all three still report healthy.

### 2.6 Register in `targets/default.nix`

```nix
etcd-cluster = {
  description = "Three-node etcd Raft cluster target";
  topologyTarget = ./topology/etcd-cluster.nix;
  configTarget   = ./config/etcd.nix;
  baseModule     = ./etcd-cluster/module.nix;
  testScript     = ./etcd-cluster/test-script.py;
  properties     = ./etcd-cluster/properties.nix;
  reportNode     = "etcd1";
};
```

## Phase 3 — New SUT: `postgres-cluster` (primary + replica)

### 3.1 `targets/topology/postgres-cluster.nix`

```nix
{ lib, ... }:

{
  roles.primary = [ 1 ];
  roles.replica = [ 1 ];
  primaryVlans = [ [ 1 ] ];
  replicaVlans = [ [ 1 ] ];
}
```

### 3.2 `targets/config/postgres.nix`

```nix
{ lib, ... }:

{
  virtualisation.memorySize = [ 512 1024 2048 ];

  services.postgresql.enable        = [ false true ];
  services.postgresql.settings.wal_level              = [ "replica" "logical" ];
  services.postgresql.settings.max_wal_senders        = [ 3 10 ];
  services.postgresql.settings.max_replication_slots  = [ 3 10 ];

  # Tight checkpoint — exposes fsync / WAL pressure on slow VMs
  services.postgresql.settings.checkpoint_timeout = [ "30s" "5min" ];
}
```

### 3.3 `targets/postgres-cluster/`

- `primary.nix` — enables replication, sets `wal_level`, creates a `replicator` role with `REPLICATION` privilege, writes a `pg_hba.conf` rule for the replica.
- `replica.nix` — runs a `pg_basebackup` on first boot (systemd `ExecStartPre` if the `services.postgresql.replication` NixOS option isn't enough), then starts the replica with `-c primary_conninfo`.

### 3.4 `targets/postgres-cluster/test-script.py`

```python
start_all()
primary.wait_for_unit("postgresql")
replica.wait_for_unit("postgresql")
primary.succeed("psql -c \"CREATE TABLE t (v INT); INSERT INTO t VALUES (42);\"")
replica.wait_until_succeeds("psql -tAc 'SELECT v FROM t' | grep 42", timeout=30)
```

### 3.5 `targets/postgres-cluster/properties.nix`

- `replica_catches_up` — write on primary, read on replica within 30 s, value matches.
- `write_is_durable` — `systemctl restart postgresql` on primary, then re-read from primary, value still there.
- `replica_lag_below_threshold` — `SELECT EXTRACT(EPOCH FROM now() - pg_last_xact_replay_timestamp())` on replica < 10 s.
- `both_nodes_listening` — both `primary` and `replica` have port 5432 open.

### 3.6 Register in `targets/default.nix`

```nix
postgres-cluster = {
  description = "PostgreSQL primary + streaming replica target";
  topologyTarget = ./topology/postgres-cluster.nix;
  configTarget   = ./config/postgres.nix;
  baseModule     = ./postgres-cluster/primary.nix;   # NB: see note below
  testScript     = ./postgres-cluster/test-script.py;
  properties     = ./postgres-cluster/properties.nix;
  reportNode     = "primary";
};
```

**Open question for Phase 3:** the current `baseModule` slot in `targets/default.nix` is a single path. PostgreSQL primary and replica need *different* modules. Two options:

1. Refactor `lib/runner.nix` to accept per-role base modules (mirrors how per-role fuzzed config already works). Small Nix change, ~30 lines.
2. Fold the per-role difference into the topology map and a single module that branches on `nodeName`. Quicker, less clean.

Default to **option 1** because it generalizes; fall back to option 2 only if the refactor breaks kafka-cluster / etcd-cluster.

## Phase 4 — Sweep & shrink

For each SUT, once Phase 1/2/3 is green:

```bash
# 1. Smoke 3 seeds
python3 -m topotestix.cli orchestrator run <target> --seed 1 --project-root .
python3 -m topotestix.cli orchestrator run <target> --seed 2 --project-root .
python3 -m topotestix.cli orchestrator run <target> --seed 3 --project-root .

# 2. Full sweep (sequential, build cache reused)
python3 -m topotestix.cli orchestrator sweep <target> --seeds 1..50 --project-root .

# 3. List failures
python3 -m topotestix.cli runs list --project-root .

# 4. Shrink each failure, save the printed reproduceCommand
python3 -m topotestix.cli orchestrator shrink <target> <seed> --project-root .
```

Expected wall-clock (after first build):
- kafka-cluster: ~2 h for 50 seeds (3 VMs, JVM startup)
- etcd: ~1 h
- postgres: ~1 h

Total: ~1 working day of background runs.

## Phase 5 — Thesis empirical chapter

Chapter skeleton, mapped 1:1 to what we'll have:

1. **Setup** — SUT list, hardware, NixOS version, total wall-clock, seed budget.
2. **Per-SUT results table** — SUT | seeds | passes | failures | distinct failure classes | mean shrink reduction.
3. **Case studies** — 2–3 shrunk minimal repros (one per SUT), each with the failing `testScript` snippet, the shrunk `topologyChoices` + `configChoices`, the `reproduceCommand`, and a one-paragraph analysis.
4. **Cross-SUT observations** — e.g., "all three SUTs surface failures when memory is small, but only Raft-based ones expose partition-induced split-brain behavior."
5. **Threats to validity** — small sample, VM-level not bare-metal, single NixOS version, no real-network latency.

## Out of scope (explicit, for this phase)

- Phase 7 (parallel multi-execution). Sequential 50-seed sweep is fine.
- Phase 8 items other than the failure-reproducing flake (deferred; build last if time permits).
- New fuzz combinators (`dependent`, weighted shrinking, NixOS-default baseline).
- Library refactors beyond what Phase 3 of this plan needs for per-role base modules.

## Open decisions (please confirm before I start)

1. **SUT count**: 4 SUTs (kafka-cluster expanded + etcd + postgres + nginx as smoke) is the plan. Drop nginx entirely from the repo if you want a tighter codebase?
2. **Seed budget**: 50 per SUT. Drop to 30 if time is tight; go to 100 only if Phase 4 produces interesting failures early.
3. **Properties per SUT**: 3–4 each as drafted. Add node-killing / partition injection properties (more interesting case studies, ~half a day more work)?
4. **Phase 3 base-module refactor**: option 1 (clean) vs option 2 (quick). Default to option 1; flag if you want me to start with option 2.
