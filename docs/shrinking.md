# TopoTestix Shrinking

## Overview

Shrinking finds the minimal configuration that still triggers a failing test. When a fuzzer-generated config fails a property, the shrinker systematically simplifies it by reducing choice indices toward 0 (where lower index = simpler value in target specs).

The approach is **choice-based shrinking**, inspired by Hypothesis's internal representation: instead of manipulating seeds (which don't correlate with simplicity), we directly manipulate the individual choices the fuzzer made.

## Why Not Seed-Based Shrinking?

The simplest shrinking approach is to try smaller seed numbers: seed 1, 2, 3, ... and keep the smallest seed that still fails. This is easy to implement but has a fundamental problem:

**Lower seeds don't produce simpler configs.** The fuzzer maps `seed → hash → mod → index`. Seed 1 might produce `{ roles.broker=3, memorySize=4096 }` while seed 3 might produce `{ roles.broker=1, memorySize=512 }`. The mapping is essentially random — there is no monotonic relationship between seed value and config simplicity.

Seed-based shrinking finds "smallest seed that still fails," not "simplest config that still fails."

## Choice-Based Shrinking

Each leaf in the target spec is a choice point — a list of options where the fuzzer picks one index. The shrinker reduces individual choice indices toward 0. Since target specs conventionally order options from simplest to most complex, lower indices produce simpler configs.

### Convention: Lower Index = Simpler

Target spec authors must order options from simplest to most complex:

```nix
{
  roles.broker = [ 1 2 3 ];             # index 0 = fewest brokers
  memorySize = [ 512 1024 2048 4096 ];   # index 0 = least memory
  vlans = [ [ 1 ] [ 1 10 ] ];           # index 0 = simplest network
  enable = bool;                         # false (index 0) is simpler
}
```

This convention makes shrinking direction-independent: always move toward index 0.

### Boolean convention

`bool` is defined as `[ false true ]` so that index 0 = false (simpler). A disabled service is simpler than an enabled one.

---

## Pipeline

```
(seed, target) ──→ fuzzer ──→ { result, choices }
                                    │         │
                                    ▼         │
                              (result, ...    │
                               choices)       │
                                    │         │
                                    ▼         │
                               shrinker ◄─────┘  (adjusts choices)
                                    │
                                    ▼
                              test_options
                                    │
                                    ▼
                              expand/merge/runner
                                    │
                                    ▼
                              report
                                    │
                                    ▼
                         orchestrator ──→ pass? new seed : shrink further
```

Full granular pipeline:

```
(seed, topology_target) → fuzzer → { fuzzed_topology, topology_choices }
(fuzzed_topology, topology_target, topology_choices_shrunk) → shrinker → test_topology
test_topology → expand_topology → test_topology_options

(seed, config_target) → fuzzer → { fuzzed_config, config_choices }
(fuzzed_config, config_target, config_choices_shrunk) → shrinker → test_config

(test_config, test_topology_options, base) → merge → node_configs
(node_configs, test_script, properties) → runner → report
report → orchestrator → pass? fuzzer with new seed : shrinker with updated choices
```

The shrinker sits between fuzzer output and expandTopology/merge input. When choices are empty (no shrinking), the shrinker returns fuzzer output unchanged (identity).

---

## Fuzzer Changes

The fuzzer currently returns a flat attrset. It must be updated to also return the choices map — the index the fuzzer selected for each path.

### Interface change

**Before:**
```nix
fuzzer { seed = "42"; target = { memorySize = [512 1024 2048 4096]; }; }
# => { memorySize = 2048; }
```

**After:**
```nix
fuzzer { seed = "42"; target = { memorySize = [512 1024 2048 4096]; }; }
# => {
#   result  = { memorySize = 2048; };
#   choices = { ".memorySize" = 2; };   # index 2 → value 2048
# }
```

The `choices` attrset maps target-relative dot-separated paths to the index the fuzzer chose. The seed is used only in the internal hash key for deterministic selection; it is not included in public choice keys. Python can pass these keys directly to `shrinker.apply`.

### Combinators change

`combinators.resolve` must be updated to also track choices. This requires passing an accumulator alongside the resolved value:

```nix
# resolve now returns { value, choices } at each leaf
resolve = prefix: value:
  if builtins.isList value then
    let idx = lib.mod (toInt prefix) (builtins.length value);
    in { value = builtins.elemAt value idx; choices = { "${prefix}" = idx; }; }
  else if builtins.isAttrs value then
    let result = lib.mapAttrs (n: v: resolve "${prefix}.${n}" v) value;
    in {
      value    = lib.mapAttrs (n: v: v.value) result;
      choices  = lib.foldl' (acc: v: acc // v.choices) {} (lib.attrValues result);
    }
  else if builtins.isFunction value then
    resolve prefix (value { inherit lib; })
  else
    { value = value; choices = {}; };
```

The fuzzer then returns `{ result = resolved.value; choices = resolved.choices; }`.

### Backward compatibility

Existing code that calls `fuzzer { ... }` and expects a flat attrset must be updated to use `.result`. This affects `orchestrate.nix` and the smoke test.

---

## Shrinker Module

### Interface

```nix
# lib/shrinker.nix
{ lib }:

let
  # ... internal helpers ...
in
{
  # Apply choice overrides to fuzzed output.
  # Replaces values at specified paths with the value at the given index in the target's option list.
  # Identity when choices_override is empty.
  apply = target: fuzzed: choices_override: ...;

  # List all choice paths in a target spec (paths where the value is a list).
  # Used by Python to know which dimensions are available for shrinking.
  choicePaths = target: [ ".virtualisation.memorySize" ".roles.broker" ... ];

  # Get the value at a specific index in a target's option list.
  # Used by Python to display what each index maps to.
  valueAt = target: path: index: ...;

  # Get the full option list for a path.
  # Used by Python to know the range of valid indices.
  optionsFor = target: path: [ 512 1024 2048 4096 ];
}
```

### `apply`

```nix
# Re-resolves the target, but forces specific paths to specific indices.
# When choices_override has { ".memorySize" = 0; }, the value at .memorySize
# becomes target.memorySize[0] instead of the fuzzer's choice.
apply = target: fuzzed: choices_override:
  applyOverrides target fuzzed choices_override;
```

The implementation re-walks the target, and for each path present in `choices_override`, uses the specified index instead of the hash-based one. For paths not in `choices_override`, it uses the values from `fuzzed` (preserving the fuzzer's original choices).

### `choicePaths`

Walks the target attribute set depth-first, collecting all paths where the value is a list:

```nix
choicePaths = target:
  collectPaths "" target;

collectPaths = prefix: value:
  if builtins.isList value then [ prefix ]
  else if builtins.isAttrs value then
    lib.concatMap (n: collectPaths "${prefix}.${n}" value.${n}) (builtins.attrNames value)
  else if builtins.isFunction value then
    collectPaths prefix (value { inherit lib; })
  else [];
```

### `valueAt` and `optionsFor`

```nix
# Get the value at a specific index for a path in the target
valueAt = target: path: index:
  let options = getValueByPath target path;
  in builtins.elemAt options index;

# Get the full option list for a path
optionsFor = target: path:
  getValueByPath target path;
```

These are utilities for the Python orchestrator to query the target structure via `nix eval`.

---

## Orchestrator Integration

### `orchestrate.nix` changes

Add `topologyChoices` and `configChoices` parameters:

```nix
orchestrate = { seed
              , topologyTarget
              , configTarget
              , baseModule
              , testScript
              , properties
              , name
              , reportNode ? null
              , topologyChoices ? {}    # NEW: shrinker overrides for topology
              , configChoices ? {}       # NEW: shrinker overrides for config (per-role)
              }:
  let
    fuzzedTopology = fuzzerMod.fuzzer { seed = seedStr; target = topologyTarget; };

    testTopology = shrinker.apply topologyTarget fuzzedTopology.result topologyChoices;

    expansion = expandTopologyMod.expandTopology { topology-map = testTopology; };

    roleConfigs = builtins.listToAttrs (lib.imap0 (idx: roleName:
      let
        roleSeed = toString (seed + 1 + idx);
        fuzzedRole = fuzzerMod.fuzzer { seed = roleSeed; target = configTarget; };
        roleChoices = configChoices.${roleName} or {};
        testRoleConfig = shrinker.apply configTarget fuzzedRole.result roleChoices;
      in { name = roleName; value = testRoleConfig; }
    ) roleNames);

    # ... rest unchanged ...
```

### Python `topotestix.orchestrator` — `shrink` mode

```python
def shrink(master_seed, args):
    # Pass 1: Evaluate fuzzer to get initial choices and structure
    fuzzed_result = nix_eval_fuzzer(master_seed, args)
    topology_choices = fuzzed_result['topology']['choices']
    role_configs = fuzzed_result['role_configs']

    # Get all choice paths for each dimension
    topo_paths = nix_eval_choice_paths(args.topology_target)
    config_paths = nix_eval_choice_paths(args.config_target)

    # Initialize accumulated choices (empty = no shrinking)
    topo_overrides = {}
    config_overrides = {}  # { role_name: { path: index } }

    # Shrink topology dimension
    for path in topo_paths:
        current_index = topology_choices[path]
        for index in range(current_index - 1, -1, -1):
            new_overrides = {**topo_overrides, path: index}
            result = build_and_run(master_seed, args, topology_choices=new_overrides, config_choices=config_overrides)
            if result.failed:
                topo_overrides[path] = index
                break
            # else: this simpler value doesn't trigger the bug, try next

    # Shrink each role config dimension
    for role_name in role_configs:
        role_overrides = config_overrides.get(role_name, {})
        for path in config_paths:
            current_index = role_configs[role_name]['choices'][path]
            for index in range(current_index - 1, -1, -1):
                new_overrides = {**role_overrides, path: index}
                config_overrides[role_name] = new_overrides
                result = build_and_run(master_seed, args, topology_choices=topo_overrides, config_choices=config_overrides)
                if result.failed:
                    role_overrides[path] = index
                    break

    # Output: minimal overrides map
    print(f"Minimal topology overrides: {topo_overrides}")
    print(f"Minimal config overrides: {config_overrides}")
```

### Reproduction

Shrunk cases are reproduced with overrides, not just a seed:

```bash
python3 -m topotestix.cli orchestrator run kafka-cluster --seed 42 --project-root . \
  --topology-choices '{".roles.broker": 0}' \
  --config-choices '{"broker": {".virtualisation.memorySize": 0}}'
```

### Nix eval queries for shrinking

The Python orchestrator uses `nix eval --json` to query the shrinker module:

```bash
# Get all choice paths for a target
nix eval --impure --json --expr '
  let
    shrinker = import ./lib/shrinker.nix { inherit lib; };
    target = import ./targets/nginx/config.nix { inherit lib; };
  in shrinker.choicePaths target
'

# Get the current choice index for a path
nix eval --impure --json --expr '
  let
    fuzzer = (import ./lib/fuzzer.nix { inherit lib; }).fuzzer;
    result = fuzzer { seed = "42"; target = import ./targets/nginx/config.nix { inherit lib; }; };
  in result.choices
'
```

---

## Design Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Choice-based shrinking (not seed-based) | Lower indices = simpler values | Seeds don't correlate with simplicity; target spec ordering is meaningful |
| Separate shrinker module from fuzzer | `lib/shrinker.nix` | Different responsibilities: fuzzer generates, shrinker simplifies. Testable independently. |
| Shrinker operates on `target + fuzzed + choices` | Three inputs needed | Shrinker needs target spec (option lists), fuzzed result (current values), and choices (indices to override). Can't resolve choices without target. |
| Python drives shrinking loop | Nix is pure, no side effects | Shrinking requires iteration and branching based on test results. Python orchestrates; Nix evaluates. |
| Shrinker is identity on empty choices | No overrides = no change | Normal (un-shrunk) pipeline works without any shrinking logic. |
| `bool` = `[false true]` | Index 0 = false | Consistent with "lower index = simpler" convention. Disabled services are simpler. |
| Fuzzer returns `{ result, choices }` | Choices alongside values | Python needs indices to drive shrinking; choices map is compact (integers) and avoids re-serializing Nix values. |
| Choices are target-relative path strings (e.g. `".virtualisation.memorySize"`) | Dot-separated paths with a leading dot | The seed is used only in the hash key, so fuzzer choices are directly usable with `shrinker.apply`. |
| Per-dimension independent shrinking | Each dimension shrunk separately | Topology, then each role config. Preserves independence between dimensions. |

---

## Future Considerations

### NixOS defaults as minimal values

Currently, "simplest" = first element in target spec option list. A future improvement could use NixOS default values as the minimal baseline, since NixOS defaults represent the "most common" or "safest" configuration. This would require querying the NixOS module system at eval time.

### Error-prone shrinking direction

"Simpler" configs can be more error-prone (less memory → OOM, fewer nodes → quorum loss). The current direction (minimize) is correct for finding minimal reproduction, but a future improvement could weight shrink direction based on observed failure modes, or allow bidirectional shrinking.

### Inter-field constraint shrinking

Inter-field dependent combinators are future work. If they are added, shrinking will need a constraint-aware policy for overrides that make one field inconsistent with another.

### Shrinking order

Currently: topology first, then each role config, each path in order, each index from current-1 down to 0. Future improvements:
- Try the most impactful paths first (heuristic: paths with larger index ranges).
- Binary search instead of linear (try midpoint first, then binary-search down).
- Parallelize: build multiple candidates simultaneously.

---

## References

- [Hypothesis: How Shrinking Works](https://hypothesis.works/articles/how-shrinking-works/) — shrinking by minimizing the internal choice representation
- [QuickCheck Paper](https://www.cs.tufts.edu/~nr/cs257/archive/john-hughes/quick.pdf) — original PBT paper, type-directed shrinking
- [PropEr: Property-Based Testing](https://propertesting.com/) — chapters on shrinking strategies
