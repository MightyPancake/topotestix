# TopoTestix Merge Module

Config merging utilities for composing NixOS configurations. Standalone module in `lib/merge.nix`, separate from the runner — same pattern as `expand-topology.nix` being separate from the fuzzer. Merge is an orchestration concern, not a runner concern.

## Interface

```nix
# lib/merge.nix
{ lib }:

{
  mkForceAttrs   # recursively apply lib.mkForce to all leaf values
  mergeConfigs   # three-layer merge: base ⊕ config ⊕ topology
}
```

## `mkForceAttrs`

Recursively applies `lib.mkForce` to all leaf values in an attrset. Fuzzed config and topology layers get mkForce so they override base config values.

```nix
mkForceAttrs { services.nginx.enable = true; virtualisation.memorySize = 2048; }
# => { services.nginx.enable = mkForce true; virtualisation.memorySize = mkForce 2048; }
```

Traverses the attrset depth-first. Lists and non-attrset values are leaves — they get `mkForce`. Nested attrsets are recursed into. This means a fuzzed value like `virtualisation.memorySize = 4096` becomes `virtualisation.memorySize = mkForce 4096`, giving it priority 50 over any default value in base config.

## `mergeConfigs`

Three-layer merge: `base ⊕ config ⊕ topology`. Base is kept plain (no mkForce). Config and topology layers are mkForce'd before merging, giving them priority over base.

```nix
mergeConfigs {
  base = { services.nginx.enable = true; virtualisation.memorySize = 1024; };
  config = { virtualisation.memorySize = 4096; };     # overrides base via mkForce
  topology = { virtualisation.vlans = [1 10]; };       # overrides base via mkForce
}
# => { services.nginx.enable = true; virtualisation.memorySize = mkForce 4096; virtualisation.vlans = mkForce [1 10]; }
```

Equivalent to:

```nix
lib.recursiveUpdate (lib.recursiveUpdate baseConfig (mkForceAttrs fuzzedConfig)) (mkForceAttrs topologyConfig)
```

### Layer precedence

| Layer | mkForce? | Priority | Example |
|---|---|---|---|
| **Base config** | No | Default (100) | `services.nginx.enable = true` |
| **Fuzzed target config** | Yes | 50 (overrides base) | `virtualisation.memorySize = mkForce 4096` |
| **Fuzzed topology config** | Yes | 50 (overrides base) | `virtualisation.vlans = mkForce [1 10]` |

When config and topology both set the same key, topology wins (last `recursiveUpdate` wins). This is intentional: topology constraints (like VLAN assignments) should override per-node fuzzed values if they conflict.

**Edge case: config-topology conflicts with equal priority.** Both config and topology layers use `mkForce` (priority 50). When they set the same key, `recursiveUpdate` takes the rightmost value — topology. However, if in practice a config fuzzed value and a topology fuzzed value clash on the *same* key with *different* desired outcomes, `mkForce` priority alone doesn't resolve this — both are priority 50, and topology simply wins by position. This is not currently handled as an error or warning. In practice, config targets and topology targets should not overlap on the same keys (they fuzz different dimensions: config fuzzez service/resource settings, topology fuzzes network/VLAN settings), so this conflict should not arise. If it does, topology silently wins.

### Single-node vs multi-node

For single-node tests, only base and config layers are merged:

```nix
mergeConfigs { base = baseConfig; config = fuzzedConfig; }
```

For multi-node tests, all three layers are merged per node:

```nix
mergeConfigs {
  base = baseConfig;
  config = fuzzedConfigs.broker1;
  topology = topologyConfigs.broker1;
}
```

The orchestrator calls `mergeConfigs` once per node.

## Design decisions

| Decision | Choice | Rationale |
|---|---|---|
| Separate module from runner | `lib/merge.nix` not inside `lib/runner.nix` | Same pattern as `expand-topology.nix` — pure orchestration utility, not a runner concern |
| mkForce on fuzzed layers only | Base is plain, config and topology get mkForce | Fuzzer outputs pure attrsets; priority is applied at merge time |
| Topology wins over config on conflicts | Topology is the last `recursiveUpdate` | Topology constraints (VLANs) should override per-node fuzzed values |
| Uses `lib.recursiveUpdate` | Standard NixOS merge | Consistent with how NixOS modules compose configs |