# TopoTestix Orchestrator

Central coordinator that drives the full pipeline: fuzzer → expandTopology → merge → runner → build → report.

## Two-Layer Architecture

The orchestrator has two components:

1. **`lib/orchestrate.nix`** — Nix function that composes the full pipeline
2. **`orchestrator/orchestrator.py`** — Python CLI that generates a Nix expression, calls `nix build`, parses `report.json`

All Nix-type computation (fuzzer, expandTopology, mkForce merge) must happen in Nix — these values can't be serialized through Python. Python is a thin CLI wrapper: generate temp `.nix` file → `nix build --impure` → parse `report.json`.

`lib/orchestrate.nix` is the real pipeline logic and is testable with `nix-unit`. `orchestrator.py` handles CLI args, path resolution, temp file generation, build execution, and result parsing.

## Data Flow (Single Pass — Phase 2)

```
User provides:
  --seed,
  --config-target, 
  --topology-target, 
  --base-module, 
  --test-script, 
  --properties, 
  --name

orchestrator.py:
  1. Resolve all paths to absolute
  2. Generate temp .nix file that calls orchestrate.nix
  3. nix build --impure --file tempfile.nix -o result-link
  4. Parse result-link/report.json
  5. Print summary

lib/orchestrate.nix (inside the temp file):
  1. fuzzer(seed + 0, topologyTarget) → topology-map
  2. expandTopology(topology-map) → nodeConfigs + nodeRoles
  3. For each role (alphabetical): fuzzer(seed + 1 + roleIndex, configTarget) → roleConfig
  4. For each node: mergeConfigs(base, roleConfig[nodeRoles[node]], topologyConfig[node])
  5. runner.run(nodeConfigs, testScript, properties, name) → NixOS test derivation
```

## Seed Derivation

All seeds derived from a single `master_seed`:

| Seed offset | Purpose | Example (master_seed=5) |
|---|---|---|
| +0 | topology | "5" |
| +1 + roleIndex | per-role config | broker: "6", controller: "7" |

Role ordering is alphabetical: sorted role names determine `roleIndex`.

```
master_seed = 5, roles = [broker, controller]

seed map:
  topology:   "5"  (master_seed + 0)
  broker:     "6"  (master_seed + 1 + 0)
  controller: "7"  (master_seed + 1 + 1)
```

All nodes of the same role share one fuzzer call (identical config). Seed is converted to string because the fuzzer uses string seeds for hashing.

## Node Naming: Always Indexed

expandTopology names all nodes with `roleName + 1-based index`:

```
roles = { broker = 2; controller = 1; }
→ broker1, broker2, controller1
```

No special cases, no conditional naming. Count=1 still gets index: `machine1`, not `machine`.

Rationale:
- Predictable and consistent
- Decoupled from fuzzed count — names don't change when the fuzzer varies `nodeCount`
- No name changes between different topology seeds

Impact: single-node test scripts use `machine1` instead of `machine`.

## expandTopology Enhancement: nodeRoles

expandTopology now returns `{ nodeConfigs, nodeRoles }` instead of just the node attrset:

```nix
expandTopology {
  topology-map = {
    roles = { broker = 2; controller = 1; };
    brokerVlans = [ 1 ];
    controllerVlans = [ 2 10 ];
  };
}
# => {
#   nodeConfigs = {
#     broker1     = { virtualisation.vlans = [ 1 ]; };
#     broker2     = { virtualisation.vlans = [ 1 ]; };
#     controller1 = { virtualisation.vlans = [ 2 10 ]; };
#   };
#   nodeRoles = {
#     broker1     = "broker";
#     broker2     = "broker";
#     controller1 = "controller";
#   };
# }
```

`nodeConfigs` is the same attrset as before (just wrapped in a record). `nodeRoles` maps each node name to its role name. This lets orchestrate.nix look up which role config applies to each node.

## Properties: Include All

`orchestrate.nix` uses `builtins.attrValues propertiesModule` to include all properties from the module:

```nix
properties = builtins.attrValues (import /path/to/properties.nix { inherit lib; });
```

The user defines which properties exist by choosing the properties module. Adding a new property to the module automatically includes it in testing.

Future addition: selective property inclusion via `--property-name` CLI flag.

## The `pkgs` Problem and Multi-Node Merge

Base modules are functions `{ pkgs, ... }: { ... }` — they need `pkgs` in scope, which only exists inside the NixOS module system. The three-layer merge must happen inside each node's module function:

```nix
nodeConfigs = lib.mapAttrs (nodeName: nodeTopoConfig:
  { pkgs, ... }:
    mergeConfigs {
      base = baseModule { inherit pkgs; };
      config = roleConfigs.${nodeRoles.${nodeName}};
      topology = nodeTopoConfig;
    }
) topologyNodeConfigs;
```

This is the same pattern as the nginx smoke test, generalized for multi-node.

## `lib/orchestrate.nix` Interface

```nix
# lib/orchestrate.nix
{ pkgs, lib, testers }:

{ seed              # integer: master seed
, topologyTarget    # Nix attrset: topology fuzz target
, configTarget      # Nix attrset: config fuzz target
, baseModule        # Nix module function: { pkgs, ... }: { ... }
, testScript        # string: Python test script content
, properties        # attrset: properties module (all properties included)
, name              # string: test name
, reportNode ? null  # string: node that writes report (defaults to first node)
}:
```

Returns a NixOS test derivation (result of `runner.run`).

## CLI Interface

```
orchestrator.py run \
  --seed 5 \
  --topology-target targets/topology/simple-cluster.nix \
  --config-target targets/config/nginx.nix \
  --base-module targets/nginx/module.nix \
  --test-script targets/nginx/test-script.py \
  --properties targets/nginx/properties.nix \
  --name nginx-smoke
```

All paths relative to project root (auto-detected or via `--project-root`). `--topology-target` is **required** — always provide a topology, even for single-node tests.

## `orchestrator.py` Structure

```python
def generate_nix_expr(args) -> str:
    """Generate a Nix expression string that calls orchestrate.nix."""

def build_test(nix_expr: str, output_link: str) -> subprocess.CompletedProcess:
    """Run nix build --impure --file with the generated expression."""

def parse_report(result_path: str) -> list[dict]:
    """Read and parse report.json from the build output."""

def main():
    """CLI entry point: parse args, generate expr, build, parse report, print summary."""
```

## How Python Passes Paths to Nix

Python generates a temp `.nix` file containing a `let ... in` expression that imports all the necessary modules and calls `orchestrate.nix`. This is the same approach as `run-smoke-test.sh`:

```nix
let
  nixpkgs = builtins.getFlake "nixpkgs";
  pkgs = nixpkgs.legacyPackages.x86_64-linux;
  lib = pkgs.lib;

  topotestixLib = import /abs/path/to/lib { inherit lib; };
  runner = import /abs/path/to/lib/runner.nix { inherit pkgs lib; testers = pkgs.testers; };
  orchestrate = import /abs/path/to/lib/orchestrate.nix { inherit pkgs lib; testers = pkgs.testers; };

  configTarget = import /abs/path/to/targets/config/nginx.nix { inherit lib; };
  topologyTarget = import /abs/path/to/targets/topology/single-machine.nix { inherit lib; };
  baseModule = import /abs/path/to/targets/nginx/module.nix;
  propertiesMod = import /abs/path/to/targets/nginx/properties.nix { inherit lib; };
  testScript = builtins.readFile /abs/path/to/targets/nginx/test-script.py;
in
orchestrate {
  seed = 5;
  inherit topologyTarget configTarget baseModule testScript;
  properties = builtins.attrValues propertiesMod;
  name = "nginx-smoke";
}
```

Python resolves all paths to absolute, generates this file to a temp location, and runs `nix build --impure --file tempfile.nix -o result-link`.

## Shrinking (Future — Phase 6)

Phase 2 implements single-pass execution. Shrinking comes later with a two-pass approach:

**Pass 1**: `nix eval --json` to evaluate topology and learn role names and structure.

**Pass 2**: Build the full test with specific seeds per dimension.

Two shrinking approaches, by priority:

| Approach | Method | Phase | Trade-off |
|---|---|---|---|
| **A: Move the seed** | Try smaller seed numbers per dimension | Phase 6 | Fast, reproducible. Finds "smallest seed that still fails," not necessarily simplest config |
| **B: Move the values** | Manipulate generated config values directly (requires fuzzer per-path overrides) | Future | Finds truly minimal config. Requires enhancing fuzzer to accept overrides |
  
Per-dimension shrinking: manipulate each seed independently (topology, per-role config). Result is "smallest seed per dimension that still triggers the failure."

```
Shrinking process (Phase 6):

for master_seed in seeds:
    result = run(master_seed)
    if result.failed:
        # Shrink topology dimension
        for topo_seed in range(1, master_seed):
            result = run_with_seeds(topology_seed=topo_seed, role_seeds=original_role_seeds)
            if result.failed:
                minimal_topology_seed = topo_seed
                break
        # Shrink each role dimension
        for role in roles:
            for role_seed in range(1, original_role_seed):
                ...
```

## Phase 2 Implementation Scope

Files to create or modify:

| File | Action |
|---|---|
| `lib/orchestrate.nix` | **Create** — full pipeline function |
| `orchestrator/orchestrator.py` | **Rewrite** — CLI with `run` subcommand |
| `lib/expand-topology.nix` | **Update** — return `{ nodeConfigs, nodeRoles }` |
| `targets/nginx/test-script.py` | **Update** — `machine` → `machine1` |
| `targets/nginx/properties.nix` | **Update** — `machine` → `machine1` |
| `targets/topology/single-machine.nix` | **Create** — trivial topology for single-node tests |
| `tests/expand-topology-test.nix` | **Update** — new output structure with nodeRoles |
| `docs/plan.md` | **Update** — check off phase 2 items |

## Future Additions (Not Phase 2)

- Selective property inclusion via `--property-name` CLI flag
- Shrinking (Phase 6) — per-dimension seed manipulation, two-pass approach
- Value-based shrinking — manipulate generated values directly
- Multi-seed execution / parallel builds (Phase 7)
- TUI (Phase 5)
- Failure-reproducing flake output
- Runner as HTTP service
