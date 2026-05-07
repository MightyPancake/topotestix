# TopoTestix Architecture

## Module Overview

Three modules, with the **orchestrator** as the central coordinator:

```
 ┌──────────────────────────────────────────────────────┐
 │                   Orchestrator                       │
 │                   (Python CLI)                       │
 │                                                      │
 │  - Manages seed iteration and shrinking loop         │
 │  - Adds base config to fuzzer output                 │
 │  - Calls runner, parses report.json                  │
 │  - On failure: shrink seed, iterate                  │
 │                                                      │
 │  Future: parallel seed execution                     │
 └──────┬──────────────────────────┬────────────────────┘
        │                          │
        ▼                          ▼
 ┌───────────────┐          ┌────────────────┐
 │    Fuzzer     │          │    Runner      │
 │   (Nix lib)   │          │ (NixOS Test)   │
 │               │          │                │
 │ Two sub-mods: │          │ Inputs:        │
 │ - Config      │─────────▶│ - node configs │
 │ - Topology    │          │ - topology     │
 │               │          │ - testScript   │
 │ seed+target   │          │ - properties   │
 │ → fuzzed cfg  │          │                │
 │               │          │ Output:        │
 │               │          │ - report.json  │
 │               │          │ - stdout       │
 └───────────────┘          └────────────────┘
```

### Data Flow

```
Orchestrator (Python CLI)
  │
  ├─ seed + target ──→ Config Fuzzer ──→ fuzzed NixOS config
  ├─ seed + target ──→ Topology Fuzzer ─→ topology (nodes, links, partitions)
  │
  ├─ fuzzed config + base config + topology + testScript + properties
  │     ──→ Runner (NixOS Test) ──→ report.json / stdout
  │
  └─ report.json ──→ (if failure) shrink seed, iterate
```

---

## Directory Structure

```
topotestix/
├── lib/                          # Core Nix library
│   ├── config-fuzzer.nix         # Seed + target options → fuzzed NixOS config
│   ├── topology-fuzzer.nix       # Seed + target spec → node count, roles, links
│   ├── combinators.nix           # choose, range, bool, oneOf, dependent
│   └── properties.nix            # Property → Python assertion helpers
│
├── systems/                      # System-under-test definitions
│   ├── kafka/
│   │   ├── module.nix            # Kafka NixOS module + fuzzable options
│   │   ├── properties.nix        # Kafka-specific properties
│   │   └── test-script.py        # Kafka test procedure
│   └── etcd/
│       ├── module.nix
│       ├── properties.nix
│       └── test-script.py
│
├── orchestrator/                  # Orchestrator (Python)
│   └── orchestrator.py            # CLI entry point, seed loop, shrinking
│
├── flake.nix                      # Nix entry point — composes fuzzer + runner
└── README.md
```

---

## Module Details

### Fuzzer

Two separate sub-modules sharing a seed→choice mechanism but operating on different domains.

#### Config Fuzzer

**Input:**
- `seed` — integer, determines all random choices
- `target` — Nix attribute set of NixOS options with fuzzable value ranges

**Output:**
- Attribute set mapping seed → fuzzed NixOS config (seed as key)

```nix
configFuzzer {
  seed = 42;
  target = {
    virtualisation.memorySize = [ 512 1024 2048 4096 ];
    services.openssh.enable = [ true false ];
  };
}
# => { virtualisation.memorySize = 2048; services.openssh.enable = false; }
```

**Shrinking strategy:** simpler values (lower memory, fewer services enabled, fewer packages).

**Key:** seed (integer), not config hash. Seed-as-key preserves reproducibility directly and makes shrinking straightforward — the orchestrator tries `seed-1, seed-2, ...` to find simpler failing cases.

#### Topology Fuzzer

**Input:**
- `seed` — integer
- `target` — spec defining allowed topology types, node role ranges, network constraints

**Output:**
- Topology descriptor: node count, roles, network links, partition model

```nix
topologyFuzzer {
  seed = 42;
  target = {
    nodeCount = [ 1 3 5 ];
    topology = [ "star" "ring" "mesh" ];
    partitions = [ true false ];
  };
}
# => { nodeCount = 3; topology = "mesh"; partitions = false; nodes = { broker0 = ...; broker1 = ...; broker2 = ...; }; }
```

**Shrinking strategy:** fewer nodes, simpler topology shapes, no partitions.

#### Combinators

Both fuzzers share a common combinator language:

```nix
{
  bool      = [ true false ];
  range     = min: max: lib.genList (i: min + i) (max - min);
  oneOf     = options: options;
  dependent = name: f: { _depends = name; _fn = f; };
}
```

`dependent` handles inter-field constraints (e.g., `diskSize` must exceed `memorySize`).

---

### Runner

Based on NixOS `testers.runNixOSTest`. Thin wrapper that composes inputs into a runnable test.

**Inputs:**
- `nodeConfigs` — per-node NixOS configurations (fuzzed + base merged by orchestrator)
- `topology` — topology descriptor from topology fuzzer (how many nodes, network layout)
- `testScript` — Python test procedure provided by the user, as-is (no mutation)
- `properties` — Nix expressions generating Python assertion helper functions

**Output:**
- `report.json` — structured test results (which assertions passed/failed, which phase)
- `stdout` — fallback if report.json is not generated

The runner injects property helper functions into the testScript. Properties are called at explicit checkpoints within the test procedure:

```python
# testScript (user-provided procedure)
setup_cluster()
produce_messages()

# property checkpoint injected by runner
check_no_message_lost(produced, consumed)

restart_broker()

# another checkpoint
check_no_message_lost(produced, consumed)
```

Properties are **not** systemd services on nodes. They are Python helper functions defined in Nix, injected into the testScript by the runner. This gives them cluster-level visibility (all nodes accessible from one place) and precise timing (called at specific test phases).

If continuous monitoring is needed in the future, a lightweight systemd service on each node can write observations to a file, and the testScript reads them at checkpoints.

---

### Orchestrator

Python CLI application. Central coordinator — other modules interact through it.

**Responsibilities:**
1. Accept user input (testScript, base config, fuzz target spec)
2. Generate seeds, call fuzzer modules
3. Merge fuzzed config with base config
4. Call runner with composed inputs
5. Parse report.json / stdout from runner
6. On failure: shrink seed and iterate
7. Output summary of all runs and minimal failing cases

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

Since shrinking operates on the seed space (integers), and seeds deterministically produce configs, the orchestrator can try simpler seeds directly without understanding config internals.

**Future (not priority):** parallel seed execution — run multiple seeds concurrently, then shrink only the failing ones.

---

## Design Principles

1. **Orchestrator is central** — other modules interact through it, not with each other
2. **Config fuzzer ≠ Topology fuzzer** — different domains, different shrinking strategies, but shared combinator mechanism
3. **Seed-as-key** — seeds are the primary identifier. Reproducibility means re-running the same seed. Shrinking means trying simpler seeds.
4. **Properties are Python helpers defined in Nix** — reusable across SUTs, injected into testScript by runner, called at explicit checkpoints
5. **Fuzzer outputs only fuzzed options** — base config is added by orchestrator, keeping the fuzzer's responsibility minimal
6. **Every module usable from CLI** — fuzzer, runner, and orchestrator each have a CLI interface
7. **Lazy evaluation leveraged** — runner imports fuzzer via Nix, so only evaluated configs are built

---

## References

### Shrinking

- [QuickCheck paper](https://www.cs.tufts.edu/~nr/cs257/archive/john-hughes/quick.pdf) — original PBT paper, sections on shrinking generators
- [Hypothesis documentation — Shrinking](https://hypothesis.readthedocs.io/en/latest/data.html#shrinking) — practical shrinking explanation
- [How Hypothesis Shrinks](https://hypothesis.works/articles/how-shrinking-works/) — brief blog post on shrinking internals

### Property-Based Testing

- [Property-Based Testing with PropEr, Erlang, and Elixir](https://propertesting.com/) — free book, chapters 1-3 cover properties
- [QuickCheck state machine testing](https://video.haskell.org/video/5c196ead-e9fd-4a69-ae2c-b8f3d2e5d984) — stateful PBT deep dive
