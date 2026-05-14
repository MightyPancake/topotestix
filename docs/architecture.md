# TopoTestix Architecture

## Module Overview

Three modules, with the **orchestrator** as the central coordinator:

```
 ┌──────────────────────────────────────────────────────────────┐
 │                      Orchestrator (Python CLI)               │
 │                                                              │
 │  - Derives per-node seeds from master_seed                   │
 │  - Calls fuzzer N times (once per node, once for topology)   │
 │  - Calls expandTopology (topology-map → per-node VLANs)      │
 │  - Three-layer merge: base ⊕ config ⊕ topology               │
 │  - Calls runner, parses report.json                          │
 │  - On failure: shrink master_seed, iterate                   │
 │                                                              │
 │  Future: parallel seed execution                             │
 └────────┬────────────────────────────┬────────────────────────┘
          │                            │
          ▼                            ▼
 ┌─────────────────┐          ┌─────────────────┐
 │     Fuzzer      │          │     Runner      │
 │    (Nix lib)    │          │  (NixOS Test)   │
 │                 │          │                 │
 │  seed + target  │          │  Inputs:        │
 │  → flat attrset │─────────▶│  - node configs │
 │                 │          │  - testScript   │
 │  (called N      │          │  - properties   │
 │   times, once   │          │                 │
 │   per node)     │          │  Output:        │
 │                 │          │  - report.json  │
 └─────────────────┘          └─────────────────┘

 ┌─────────────────────┐
 │  expandTopology     │
 │  (Nix lib, no seed) │
 │                     │
 │  topology-map       │
 │  → per-node VLAN    │
 │    configs          │
 └─────────────────────┘
```

### Key Insight: Topology Is Just Multi-Node Config

In NixOS VM tests, there is no separate "topology" layer. Everything is node config:

| Topology concept | NixOS mechanism |
|---|---|
| Node count | Number of attribute sets in `nodes` |
| Network connectivity | `virtualisation.vlans` per node (list — node can be on multiple VLANs) |
| Network partitions | Nodes on different VLANs |
| Shared communication | Nodes on a common VLAN |
| Latency / packet loss | `tc` config or systemd service per node |
| Node roles | Different service configs per node |

VLANs are the only primitive needed. Nodes on the same VLAN can communicate; nodes on different VLANs cannot. A node can be on multiple VLANs (e.g., `[1 10]`), enabling mixed topologies — isolated role networks plus a shared communication VLAN.

### Three-Layer Config Composition

Each node's final config is built from three independent layers, merged by the orchestrator:

```
base config  ⊕  fuzzed target configs  ⊕  fuzzed topology configs  =  final node config
(stable)       (per-node, from fuzzer)   (per-node, from fuzzer + expandTopology)
```

| Layer | Source | Example options | Applied to |
|---|---|---|---|
| **Base config** | User-provided | `environment.systemPackages`, `services.kafka.enable` | All nodes identically |
| **Fuzzed target configs** | Fuzzer (per-node call) | `virtualisation.memorySize`, `services.openssh.enable` | Each node gets its own fuzzer call |
| **Fuzzed topology configs** | Fuzzer (topology call) + expandTopology | `virtualisation.vlans`, role-specific configs | Per-node, derived from topology-map |

```nix
# Base config (same for all nodes)
baseConfig = { services.openssh.enable = true; environment.systemPackages = [ pkgs.vim ]; };

# Fuzzed target config (one fuzzer call per node)
broker1Config     = fuzzer { seed = 43; target = configSpec; };  # => { memorySize = 2048; ... }
broker2Config     = fuzzer { seed = 44; target = configSpec; };  # => { memorySize = 1024; ... }
controller1Config = fuzzer { seed = 45; target = configSpec; };  # => { memorySize = 512; ... }

# Fuzzed topology config (one fuzzer call → topology-map, then expandTopology)
topology-map = fuzzer { seed = 42; target = topologySpec; };
# => { nodeCount = 3; brokerVlans = [1 10]; controllerVlans = [2 10]; roles = { broker = 2; controller = 1; }; }

topologyConfigs = expandTopology { inherit topology-map; };
# => { broker1.vlans = [1 10]; broker2.vlans = [1 10]; controller1.vlans = [2 10]; }

# Final composition (orchestrator merges all three per node)
finalConfigs.broker1     = recursiveUpdate (recursiveUpdate baseConfig broker1Config)     topologyConfigs.broker1;
finalConfigs.broker2     = recursiveUpdate (recursiveUpdate baseConfig broker2Config)     topologyConfigs.broker2;
finalConfigs.controller1 = recursiveUpdate (recursiveUpdate baseConfig controller1Config) topologyConfigs.controller1;
```

### Data Flow

```
Orchestrator (Python CLI)
  │
  │  master_seed = 42
  │
  ├─ fuzzer(master_seed, topology_spec)  →  topology-map (nodeCount, roles, VLANs)
  │
  ├─ expandTopology(topology-map)         →  per-node topology configs (VLAN assignments)
  │
  ├─ fuzzer(master_seed+1, config_spec)   →  broker1 target config
  ├─ fuzzer(master_seed+2, config_spec)   →  broker2 target config
  ├─ fuzzer(master_seed+3, config_spec)   →  controller1 target config
  │
  ├─ merge per node: base ⊕ target config ⊕ topology config
  │
  ├─ final node configs + testScript + properties
  │     ──→ Runner (NixOS Test) ──→ report.json / stdout
  │
  └─ report.json ──→ (if failure) shrink master_seed, iterate
```

---

## Directory Structure

```
topotestix/
├── lib/                          # Core Nix library
│   ├── fuzzer.nix                # seed + target → flat attrset (pure, no cluster awareness)
│   ├── expand-topology.nix       # topology-map → per-node VLAN configs (deterministic, no seed)
│   ├── merge.nix                 # mkForceAttrs, mergeConfigs — three-layer config composition
│   ├── combinators.nix           # choose, range, bool, oneOf, dependent
│   ├── properties.nix            # Property → Python assertion helpers
│   └── runner.nix                # composeTestScript, run — wraps runNixOSTest with harness
│
├── targets/                      # Fuzz target specs (define what to fuzz)
│   ├── config/                   # Per-node config targets
│   │   └── nginx.nix             # Example: NixOS option ranges for nginx
│   ├── topology/                  # Cluster layout targets
│   │   └── simple-cluster.nix    # Example: node count, roles, VLAN set specs
│   └── nginx/                    # SUT definition
│       ├── module.nix            # Nginx NixOS module + base config
│       ├── properties.nix        # Nginx-specific properties
│       └── test-script.py         # Nginx test procedure
│
├── orchestrator/                 # Orchestrator (Python)
│   └── orchestrator.py           # CLI entry point, seed derivation, three-layer merge, shrinking
│
├── flake.nix                     # Nix entry point — composes fuzzer + merge + runner
└── README.md
```

---

## Module Details

### Fuzzer

Pure function: `seed + target → flat attrset`. No cluster awareness, no node naming, no topology logic.

#### Mechanism

Seed → deterministic hash → choice per option. Same seed always produces the same config.

The fuzzer is called multiple times by the orchestrator — once for topology, once per node for config — each with a derived seed.

**Input:**
- `seed` — integer
- `target` — Nix attribute set describing fuzzable dimensions

**Output:**
- Flat attribute set of resolved values

```nix
fuzzer {
  seed = 43;
  target = {
    virtualisation.memorySize = [ 512 1024 2048 4096 ];
    services.openssh.enable = [ true false ];
  };
}
# => { virtualisation.memorySize = 2048; services.openssh.enable = false; }
```

```nix
fuzzer {
  seed = 42;
  target = {
    nodeCount = [ 2 3 5 ];
    roles.broker = [ 1 2 3 ];
    roles.controller = [ 1 ];
    brokerVlans = [ [1] [1 10] ];
    controllerVlans = [ [2] [2 10] ];
  };
}
# => { nodeCount = 3; roles.broker = 2; roles.controller = 1;
#      brokerVlans = [1 10]; controllerVlans = [2 10]; }
```

Note: both calls use the same mechanism. The fuzzer doesn't know or care whether it's resolving topology or config — it just picks values from lists based on a seed.

#### Combinators

Shared combinator language:

```nix
{
  bool      = [ true false ];
  range     = min: max: lib.genList (i: min + i) (max - min);
  oneOf     = options: options;
  dependent = name: f: { _depends = name; _fn = f; };
}
```

`dependent` handles inter-field constraints (e.g., `diskSize` must exceed `memorySize`).

#### Shrinking

- **Target config domain:** simpler values (lower memory, fewer services enabled, fewer packages)
- **Topology domain:** fewer nodes, simpler VLAN sets, no partitions

Since shrinking operates on the seed space (integers), the orchestrator can try simpler seeds directly without understanding config internals.

**Key:** seed (integer) as primary identifier. Not config hash. Seed-as-key preserves reproducibility and makes shrinking straightforward.

---

### expandTopology

Pure deterministic function: `topology-map → per-node VLAN configs`. No seed, no randomness.

Takes the flat output of a topology fuzzer call and mechanically expands it into per-node attribute sets.

**Input:**
- `topology-map` — flat attribute set from topology fuzzer call (nodeCount, roles, VLAN sets per role)

**Output:**
- Per-node attribute set with `virtualisation.vlans` assignments

```nix
expandTopology {
  topology-map = {
    nodeCount = 3;
    roles = { broker = 2; controller = 1; };
    brokerVlans = [1 10];
    controllerVlans = [2 10];
  };
}
# => {
#   broker1     = { virtualisation.vlans = [1 10]; };
#   broker2     = { virtualisation.vlans = [1 10]; };
#   controller1 = { virtualisation.vlans = [2 10]; };
# }
```

The expansion is deterministic: "2 brokers with VLANs `[1 10]`, 1 controller with VLANs `[2 10]`" → name nodes `broker1`, `broker2`, `controller1` and assign each their role's VLAN set.

#### VLAN Membership Model

VLANs are per-node lists. A node can be on multiple VLANs:

| VLAN setup | Meaning |
|---|---|
| `virtualisation.vlans = [1];` | Node on VLAN 1 only |
| `virtualisation.vlans = [2];` | Node on VLAN 2 only, cannot reach VLAN 1 nodes |
| `virtualisation.vlans = [1 10];` | Node on VLAN 1 (role network) and VLAN 10 (shared communication) |
| `virtualisation.vlans = [2 10];` | Node on VLAN 2 (role network) and VLAN 10 (shared communication) |

The last two create a mixed topology: brokers and controllers are isolated on their own VLANs but can communicate through the shared VLAN 10. Removing VLAN 10 creates a partition.

The target spec author defines which VLAN set combinations are valid for the SUT. The fuzzer just picks from these lists.

---

### Merge

Pure deterministic function for three-layer config composition. See [merge.md](merge.md) for full design.

**`mkForceAttrs`**: Recursively applies `lib.mkForce` to all leaf values. Used on fuzzed config and topology layers so they override base values.

**`mergeConfigs`**: `base ⊕ config ⊕ topology`. Base is plain, config and topology are mkForce'd before merging. Topology wins over config on conflicts. Both config and topology use mkForce (priority 50) — on key conflicts, topology wins by position (last `recursiveUpdate`), not by priority. In practice config and topology fuzz different dimensions (services/resources vs network/VLAN), so conflicts should not arise. See [merge.md](merge.md) for details.

Same pattern as `expandTopology` — pure function, no seed, no randomness. Called by the orchestrator (or in flake.nix), not by the runner.

---

### Runner

Based on NixOS `testers.runNixOSTest`. Thin wrapper that composes inputs into a runnable test, injects property helpers, and produces structured reports. See [runner.md](runner.md) for full design.

**Inputs:** `nodeConfigs`, `testScript`, `properties`, `name`, `reportNode`

**Output:** `report.json` (structured test results via `copy_from_machine`), test derivation pass/fail

Properties are called at explicit checkpoints via `_check()` — not auto-appended. The `_check()` function catches all exceptions and does not re-raise, so all properties are always evaluated even after failures.

---

### Orchestrator

Python CLI application. Central coordinator — other modules interact through it.

**Seed derivation:** The orchestrator derives all seeds from a single `master_seed`:
- `master_seed + 0` → topology fuzzer call
- `master_seed + 1` → node 0 (broker1) config fuzzer call
- `master_seed + 2` → node 1 (broker2) config fuzzer call
- `master_seed + N` → node N-1 config fuzzer call

This ensures reproducibility from a single seed and makes shrinking straightforward — change the master seed, and everything changes deterministically.

**Responsibilities:**
1. Accept user input (testScript, base config, config target spec, topology target spec)
2. Derive per-node seeds from master_seed
3. Call fuzzer for topology → topology-map
4. Call expandTopology(topology-map) → per-node VLAN configs
5. Call fuzzer once per node → per-node config
6. Three-layer merge: `base ⊕ per-node config ⊕ per-node topology config`
7. Call runner with composed final node configs
8. Parse report.json / stdout from runner
9. On failure: shrink master_seed and iterate
10. Output summary of all runs and minimal failing cases

**Shrinking loop (conceptual):**

```
for seed in seeds:
    result = run(seed)
    if result.failed:
        for simpler_seed in shrink(seed):
            result = run(simpler_seed)
            if result.failed:
                minimal = simpler_seed
                break
```

Since all seeds are derived from `master_seed`, shrinking one seed number shrinks the entire configuration space (topology + all node configs) simultaneously.

**Future (not priority):** parallel seed execution — run multiple seeds concurrently, then shrink only the failing ones.

---

## Design Principles

1. **Orchestrator is central** — other modules interact through it, not with each other
2. **Fuzzer is pure: seed + target → flat attrset** — no cluster logic, no node naming, no awareness of how many times it's called
3. **expandTopology is a separate pure function** — deterministic expansion, no seed, no randomness
4. **Three-layer config composition** — base config ⊕ fuzzed target configs ⊕ fuzzed topology configs = final node config, merged via `lib.recursiveUpdate`
5. **Topology outputs per-node attribute sets** — VLANs, roles are NixOS options merged like any other config layer
6. **VLAN membership is per-node lists** — enables mixed topologies (shared + isolated VLANs), partitions, and network variations
7. **Seed-as-key** — all seeds derived from master_seed. Reproducibility from one number. Shrinking is trying simpler master seeds.
8. **Properties are Python helpers defined in Nix** — reusable across SUTs, injected into testScript by runner, called at explicit checkpoints
9. **Fuzzer outputs only fuzzed options** — base config is added by orchestrator, keeping the fuzzer's responsibility minimal
10. **Every module usable from CLI** — fuzzer, expandTopology, runner, and orchestrator each have a CLI interface
11. **Lazy evaluation leveraged** — runner imports fuzzer via Nix, so only evaluated configs are built

---

## References

### Shrinking

- [QuickCheck paper](https://www.cs.tufts.edu/~nr/cs257/archive/john-hughes/quick.pdf) — original PBT paper, sections on shrinking generators
- [Hypothesis documentation — Shrinking](https://hypothesis.readthedocs.io/en/latest/data.html#shrinking) — practical shrinking explanation
- [How Hypothesis Shrinks](https://hypothesis.works/articles/how-shrinking-works/) — brief blog post on shrinking internals

### Property-Based Testing

- [Property-Based Testing with PropEr, Erlang, and Elixir](https://propertesting.com/) — free book, chapters 1-3 cover properties
- [QuickCheck state machine testing](https://video.haskell.org/video/5c196ead-e9fd-4a69-ae2c-b8f3d2e5d984) — stateful PBT deep dive
