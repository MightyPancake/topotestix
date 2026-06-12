# TopoTestix Pipeline

## Top-Level Overview

```
                                    ┌─────────────┐
                                    │   master    │
                                    │    seed      │
                                    └─────┬───────┘
                                          │
                    ┌─────────────────────┼─────────────────────┐
                    │                     │                     │
                    ▼                     ▼                     ▼
            ┌───────────────┐     ┌───────────────┐             │
            │    fuzzer     │     │    fuzzer     │             │
            │ seed + 0,     │     │ seed + 1 + i, │  (one per   │
            │ topology      │     │ config        │   role)     │
            │ target        │     │ target        │             │
            └───────┬───────┘     └───────┬───────┘             │
                    │                     │                     │
                    │   { result,         │   { result,         │
                    │     choices }       │     choices }       │
                    ▼                     ▼                     │
            ┌───────────────┐     ┌───────────────┐             │
            │   shrinker    │     │   shrinker    │             │
            │ target +      │     │ target +      │             │
            │ fuzzed +      │     │ fuzzed +       │             │
            │ choices_      │     │ choices_       │             │
            │ override      │     │ override       │             │
            └───────┬───────┘     └───────┬───────┘             │
                    │                     │                     │
                    ▼                     ▼                     │
              test_topology         test_config                 │
                    │               (per role)                  │
                    ▼                     │                     │
            ┌───────────────┐             │                     │
            │ expand        │             │                     │
            │ topology      │             │                     │
            └───────┬───────┘             │                     │
                    │                     │                     │
                    ▼                     │                     │
         test_topology_options            │                     │
                    │                     │                     │
                    └─────────┬───────────┘                     │
                              │                                 │
                              ▼                                 │
                      ┌───────────────┐                         │
                      │    merge      │                         │
                      │ base ⊕ config│                         │
                      │ ⊕ topology   │                         │
                      └───────┬───────┘                         │
                              │                                 │
                              ▼                                 │
                        node_configs                            │
                              │                                 │
                              ▼                                 │
                      ┌───────────────┐                         │
                      │    runner      │                         │
                      │ node_configs +│                         │
                      │ testScript +  │                         │
                      │ properties    │                         │
                      └───────┬───────┘                         │
                              │                                 │
                              ▼                                 │
                        report.json                             │
                              │                                 │
                              ▼                                 │
                      ┌───────────────┐                         │
                      │ orchestrator   │                         │
                      │ (Python CLI)   │                         │
                      └───────┬───────┘                         │
                              │                                 │
                              │                                 │
                 ┌────────────┴──────────┐                     │
                 │                       │                     │
             all passed?             some failed?               │
                 │                       │                     │
                 ▼                       ▼                     │
           new seed            update choices                   │
           (next iteration)    (shrink further) ───────────────┘
```

---

## Granular Pipeline

### Stage 1: Fuzz (topology)

```
Input:  (master_seed, topology_target)
Output: { result = topology_map, choices = { ".roles.broker" = 0; ".brokerVlans" = 1; ... } }

master_seed = 42
seed = str(master_seed + 0) = "42"

fuzzer {
  seed = "42";
  target = {
    roles.broker      = [ 1 2 3 ];
    roles.controller  = [ 1 ];
    brokerVlans        = [ [ 1 ] [ 1 10 ] ];
    controllerVlans    = [ [ 2 ] [ 2 10 ] ];
  };
}
# => {
#   result = {
#     roles.broker     = 2;
#     roles.controller = 1;
#     brokerVlans      = [ 1 10 ];
#     controllerVlans  = [ 2 10 ];
#   };
#   choices = {
#     ".roles.broker"       = 1;   # index 1 → value 2
#     ".roles.controller"   = 0;   # index 0 → value 1
#     ".brokerVlans"        = 1;   # index 1 → value [1 10]
#     ".controllerVlans"    = 1;   # index 1 → value [2 10]
#   };
# }
```

**Nix eval command:**

```bash
nix eval --impure --json --expr '
let
  pkgs = import <nixpkgs> {};
  lib = pkgs.lib;
  fuzzer = (import ./lib/fuzzer.nix { inherit lib; }).fuzzer;
  topologyTarget = import ./targets/topology/simple-cluster.nix { inherit lib; };
in
fuzzer { seed = "42"; target = topologyTarget; }
'
```

---

### Stage 2: Shrink (topology) — identity when no overrides

```
Input:  (topology_target, fuzzed_topology, topology_choices_override)
Output: test_topology

# No shrinking (empty overrides) — shrinker is identity:
shrinker.apply topologyTarget fuzzedTopology.result {}
# => fuzzedTopology.result  (unchanged)

# With shrinking override — replace choice at path with lower index:
shrinker.apply topologyTarget fuzzedTopology.result { ".roles.broker" = 0; }
# => {
#      roles.broker     = 1;      # overridden to index 0 → value 1 (was 2)
#      roles.controller = 1;      # unchanged from fuzzer
#      brokerVlans      = [1 10]; # unchanged from fuzzer
#      controllerVlans  = [2 10]; # unchanged from fuzzer
#    }
```

**Nix eval command:**

```bash
nix eval --impure --json --expr '
let
  pkgs = import <nixpkgs> {};
  lib = pkgs.lib;
  shrinker = import ./lib/shrinker.nix { inherit lib; };
  fuzzer = (import ./lib/fuzzer.nix { inherit lib; }).fuzzer;
  topologyTarget = import ./targets/topology/simple-cluster.nix { inherit lib; };
  fuzzedTopology = fuzzer { seed = "42"; target = topologyTarget; };
in
shrinker.apply topologyTarget fuzzedTopology.result { ".roles.broker" = 0; }
'
```

---

### Stage 3: Expand topology

```
Input:  test_topology (fuzzed + possibly shrunk)
Output: { nodeConfigs, nodeRoles }

expandTopology {
  topology-map = {
    roles.broker     = 2;
    roles.controller = 1;
    brokerVlans      = [ 1 10 ];
    controllerVlans  = [ 2 10 ];
  };
}
# => {
#   nodeConfigs = {
#     broker1     = { virtualisation.vlans = [ 1 10 ]; };
#     broker2     = { virtualisation.vlans = [ 1 10 ]; };
#     controller1 = { virtualisation.vlans = [ 2 10 ]; };
#   };
#   nodeRoles = {
#     broker1     = "broker";
#     broker2     = "broker";
#     controller1 = "controller";
#   };
# }
```

**Nix eval command:**

```bash
nix eval --impure --json --expr '
let
  pkgs = import <nixpkgs> {};
  lib = pkgs.lib;
  expandTopology = (import ./lib/expand-topology.nix { inherit lib; }).expandTopology;
  fuzzer = (import ./lib/fuzzer.nix { inherit lib; }).fuzzer;
  topologyTarget = import ./targets/topology/simple-cluster.nix { inherit lib; };
  fuzzedTopology = fuzzer { seed = "42"; target = topologyTarget; };
in
expandTopology { topology-map = fuzzedTopology.result; }
'
```

---

### Stage 4: Fuzz (per-role config)

```
Input:  (master_seed + 1 + roleIndex, config_target)
Output: { result = config_map, choices = { ".virtualisation.memorySize" = 2; ... } }

# For broker (roleIndex = 0):
seed = str(master_seed + 1 + 0) = "43"

fuzzer {
  seed = "43";
  target = {
    virtualisation.memorySize = [ 512 1024 2048 4096 ];
    services.openssh.enable   = [ false true ];      # bool convention: false first
    services.nginx.enable      = [ false true ];
  };
}
# => {
#   result = {
#     virtualisation.memorySize = 2048;
#     services.openssh.enable   = false;
#     services.nginx.enable      = true;
#   };
#   choices = {
#     ".virtualisation.memorySize" = 2;   # index 2 → value 2048
#     ".services.openssh.enable"  = 0;   # index 0 → value false
#     ".services.nginx.enable"    = 1;   # index 1 → value true
#   };
# }

# For controller (roleIndex = 1):
seed = str(master_seed + 1 + 1) = "44"
# Same target, different seed → different result and different choices
```

---

### Stage 5: Shrink (per-role config) — identity when no overrides

```
Input:  (config_target, fuzzed_config, config_choices_override)
Output: test_config

# No shrinking:
shrinker.apply configTarget fuzzedConfig.result {}
# => fuzzedConfig.result  (unchanged)

# With shrinking override:
shrinker.apply configTarget fuzzedConfig.result { ".virtualisation.memorySize" = 0; }
# => {
#      virtualisation.memorySize = 512;   # overridden to index 0
#      services.openssh.enable   = false;  # unchanged from fuzzer
#      services.nginx.enable      = true;  # unchanged from fuzzer
#    }
```

---

### Stage 6: Three-layer merge

```
Input:  base_module, test_config (per role), test_topology_options (per node)
Output: node_configs  (attrset of NixOS module functions)

# For broker1:
mergeConfigs {
  base = baseModule { inherit pkgs; };
  config = testRoleConfig_broker;
  topology = { virtualisation.vlans = [ 1 10 ]; };
}
# => { services.nginx.enable = mkForce true;
#      virtualisation.memorySize = mkForce 512;
#      virtualisation.vlans = mkForce [ 1 10 ];
#      ... base config ... }

# For controller1:
mergeConfigs {
  base = baseModule { inherit pkgs; };
  config = testRoleConfig_controller;
  topology = { virtualisation.vlans = [ 2 10 ]; };
}
# => { services.nginx.enable = mkForce false;
#      virtualisation.memorySize = mkForce 1024;
#      virtualisation.vlans = mkForce [ 2 10 ];
#      ... base config ... }
```

**Nix eval command:**

```bash
nix eval --impure --json --expr '
let
  pkgs = import <nixpkgs> {};
  lib = pkgs.lib;
  merge = import ./lib/merge.nix { inherit lib; };
in
merge.mergeConfigs {
  base = { services.nginx.enable = true; virtualisation.memorySize = 1024; };
  config = { virtualisation.memorySize = 2048; };
  topology = { virtualisation.vlans = [ 1 10 ]; };
}
'
# Note: mkForce values won't serialize cleanly to JSON;
# for testing merge behavior, use nix-unit tests instead.
```

---

### Stage 7: Runner

```
Input:  node_configs, test_script, properties, name
Output: NixOS test derivation (build → report.json)

runner.run {
  nodeConfigs = finalNodeConfigs;
  testScript = builtins.readFile ./targets/nginx/test-script.py;
  properties = builtins.attrValues (import ./targets/nginx/properties.nix { inherit lib; });
  name = "nginx-test-seed-42";
}
# => <derivation that builds NixOS VMs and runs the test>
# Build result contains: report.json with property results
```

**Build command:**

```bash
# Via the orchestrator (recommended):
nix develop -c python3 orchestrator/orchestrator.py run \
  --seed 42 \
  --topology-target targets/topology/simple-cluster.nix \
  --config-target targets/config/nginx.nix \
  --base-module targets/nginx/module.nix \
  --test-script targets/nginx/test-script.py \
  --properties targets/nginx/properties.nix \
  --name nginx-test

# Or directly via a generated Nix expression:
nix build --impure --file generated-expression.nix -o result-nginx-test
cat result-nginx-test/report.json | python3 -m json.tool
```

---

### Stage 8: Orchestrator decision loop

```
Input:  report.json
Output: decision — continue with next seed or shrink current config

if all properties passed:
    → next seed (unexplored configuration space)

if some properties failed:
    → enter shrinking mode:
        1. collect choices from fuzzer output (which indices were chosen)
        2. for each dimension (topology, then per-role config):
            for each choice path:
                for index from current_index - 1 down to 0:
                    apply override { path = index }
                    build and run test
                    if still fails → keep override, break inner loop
                    if passes    → discard override, try next index
        3. output minimal overrides map for reproduction
```

---

## Full Pipeline with Shrinking

When shrinking is active, the orchestrator drives a loop between the shrinker and the runner:

```
master_seed ──→ fuzzer ──→ { result, choices } ──→ shrinker (identity) ──→ runner ──→ report
                                         │                                          │
                                         │                                          │
                                         │                               ┌──────────┘
                                         │                               │
                                         │                          FAILED?
                                         │                               │ YES
                                         │                               ▼
                                         │                     orchestrator learns choices
                                         │                     from fuzzer output
                                         │                               │
                                         │                               ▼
                                         │                     for each choice path P:
                                         │                       for index i = current - 1 .. 0:
                                         │                         shrinker(target, fuzzed, { P: i })
                                         │                               │
                                         │                               ▼
                                         │                         ──→ runner ──→ report
                                         │                                         │
                                         │                                    still FAILS?
                                         │                                    YES → keep override, next path
                                         │                                    NO  → try next index
                                         │
                                         └───── choices dict used by Python
                                               to drive shrinking loop
```

---

## Module Interfaces Summary

| Module | File | Input | Output |
|---|---|---|---|
| **combinators** | `lib/combinators.nix` | `prefix + value` | `resolve` → `{ value, choices }`, `choose`, `bool`, `range`, `oneOf` |
| **fuzzer** | `lib/fuzzer.nix` | `{ seed, target }` | `{ result, choices }` |
| **shrinker** | `lib/shrinker.nix` | `(target, fuzzed, choices_override)` via `apply` | overridden fuzzed result |
| **expand-topology** | `lib/expand-topology.nix` | `{ topology-map }` | `{ nodeConfigs, nodeRoles }` |
| **merge** | `lib/merge.nix` | `{ base, config, topology }` via `mergeConfigs` | merged attrset (base ⊕ config ⊕ topology) |
| **properties** | `lib/properties.nix` | property definitions | `composeProperties` → `{ setup, check }` |
| **runner** | `lib/runner.nix` | `{ nodeConfigs, testScript, properties, name, reportNode }` | NixOS test derivation |
| **orchestrate** | `lib/orchestrate.nix` | `{ seed, topologyTarget, configTarget, baseModule, testScript, properties, name, reportNode, topologyChoices, configChoices }` | NixOS test derivation |

---

## Shrinker Interface Detail

```nix
# lib/shrinker.nix
{ lib }:
{
  # Apply choice overrides to fuzzed output. Identity when choices_override is empty.
  apply = target: fuzzed: choices_override: ...;

  # List all choice paths in a target spec (paths where value is a list).
  choicePaths = target: [ ".virtualisation.memorySize" ".services.nginx.enable" ... ];

  # Get the value at a specific index for a path in the target.
  valueAt = target: path: index: ...;

  # Get the full option list for a path.
  optionsFor = target: path: [ 512 1024 2048 4096 ];
}
```

**Nix eval commands for shrinking queries:**

```bash
# List all choice paths in the config target
nix eval --impure --json --expr '
let
  pkgs = import <nixpkgs> {};
  lib = pkgs.lib;
  shrinker = import ./lib/shrinker.nix { inherit lib; };
  configTarget = import ./targets/config/nginx.nix { inherit lib; };
in
shrinker.choicePaths configTarget
'
# => [ ".services.nginx.enable" ".services.openssh.enable" ".virtualisation.memorySize" ]

# Get the option list for a specific path
nix eval --impure --json --expr '
let
  pkgs = import <nixpkgs> {};
  lib = pkgs.lib;
  shrinker = import ./lib/shrinker.nix { inherit lib; };
  configTarget = import ./targets/config/nginx.nix { inherit lib; };
in
shrinker.optionsFor configTarget ".virtualisation.memorySize"
'
# => [ 512 1024 2048 4096 ]

# Get the value at a specific index
nix eval --impure --json --expr '
let
  pkgs = import <nixpkgs> {};
  lib = pkgs.lib;
  shrinker = import ./lib/shrinker.nix { inherit lib; };
  configTarget = import ./targets/config/nginx.nix { inherit lib; };
in
shrinker.valueAt configTarget ".virtualisation.memorySize" 0
'
# => 512

# Get fuzzer choices for a given seed and target
nix eval --impure --json --expr '
let
  pkgs = import <nixpkgs> {};
  lib = pkgs.lib;
  fuzzer = (import ./lib/fuzzer.nix { inherit lib; }).fuzzer;
  configTarget = import ./targets/config/nginx.nix { inherit lib; };
in
(fuzzer { seed = "42"; target = configTarget; }).choices
'
# => { ".virtualisation.memorySize" = 2; ".services.nginx.enable" = 1; ".services.openssh.enable" = 0; }

# Apply a shrinking override
nix eval --impure --json --expr '
let
  pkgs = import <nixpkgs> {};
  lib = pkgs.lib;
  shrinker = import ./lib/shrinker.nix { inherit lib; };
  fuzzer = (import ./lib/fuzzer.nix { inherit lib; }).fuzzer;
  configTarget = import ./targets/config/nginx.nix { inherit lib; };
  fuzzedConfig = fuzzer { seed = "42"; target = configTarget; };
in
shrinker.apply configTarget fuzzedConfig.result { ".virtualisation.memorySize" = 0; }
'
# => { virtualisation.memorySize = 512; services.nginx.enable = true; services.openssh.enable = false; }
```

---

## Spec Convention: Lower Index = Simpler

Target spec authors must order option lists from simplest to most complex. This convention is essential for shrinking — the shrinker always moves toward index 0.

```nix
# CORRECT — simplest values first:
{
  roles.broker = [ 1 2 3 ];             # 1 broker is simplest
  memorySize  = [ 512 1024 2048 4096 ];  # least memory is simplest
  vlans       = [ [ 1 ] [ 1 10 ] ];      # single VLAN is simplest
  enable      = bool;                     # false (index 0) is simplest
}

# WRONG — no clear ordering, shrinking will not work well:
{
  roles.broker = [ 3 1 2 ];             # not ordered
  memorySize  = [ 4096 512 1024 2048 ];   # not ordered
}
```

The `bool` combinator follows this convention: `bool = [ false true ]`, so index 0 = false (simpler).

---

## Seed Derivation

All seeds derive from a single `master_seed`:

| Offset | Purpose | Example (master_seed=42) |
|---|---|---|
| +0 | topology | seed = "42" |
| +1 + roleIndex | per-role config (alphabetical) | broker=0 → "43", controller=1 → "44" |

```
master_seed = 42, roles = [broker, controller]

seed map:
  topology:   "42"  (master_seed + 0)
  broker:     "43"  (master_seed + 1 + 0)
  controller: "44"  (master_seed + 1 + 1)
```

All nodes of the same role share one fuzzer call. The seed is converted to a string because the fuzzer uses string seeds for hashing.

---

## Putting It All Together: End-to-End Command

```bash
# Normal run (no shrinking):
nix develop -c python3 orchestrator/orchestrator.py run \
  --seed 42 \
  --topology-target targets/topology/simple-cluster.nix \
  --config-target targets/config/nginx.nix \
  --base-module targets/nginx/module.nix \
  --test-script targets/nginx/test-script.py \
  --properties targets/nginx/properties.nix \
  --name nginx-test

# Shrinking a failing seed:
nix develop -c python3 orchestrator/orchestrator.py shrink \
  --seed 42 \
  --topology-target targets/topology/simple-cluster.nix \
  --config-target targets/config/nginx.nix \
  --base-module targets/nginx/module.nix \
  --test-script targets/nginx/test-script.py \
  --properties targets/nginx/properties.nix \
  --name nginx-test

# Reproducing a shrunk case:
nix develop -c python3 orchestrator/orchestrator.py run \
  --seed 42 \
  --topology-target targets/topology/simple-cluster.nix \
  --config-target targets/config/nginx.nix \
  --base-module targets/nginx/module.nix \
  --test-script targets/nginx/test-script.py \
  --properties targets/nginx/properties.nix \
  --name nginx-test \
  --topology-choices '{".roles.broker": 0}' \
  --config-choices '{"broker": {".virtualisation.memorySize": 0}}'
```

---

## See Also

- [architecture.md](architecture.md) — module overview and design principles
- [shrinking.md](shrinking.md) — detailed shrinking design and rationale
- [orchestrator.md](orchestrator.md) — orchestrator implementation details
- [runner.md](runner.md) — runner and report harness
- [merge.md](merge.md) — three-layer config composition
- [testing.md](testing.md) — how to run and write tests
- [plan.md](plan.md) — implementation progress and phases
