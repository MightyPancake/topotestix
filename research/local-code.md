# Code Context

## Files Retrieved
1. `targets/default.nix` (41 lines) - target registry; maps CLI names to topology/config/module/script/properties/reportNode.
2. `targets/kafka-cluster/topology.nix` (6 lines) - Kafka cluster topology spec.
3. `targets/etcd-cluster/topology.nix` (6 lines) - etcd cluster topology spec.
4. `targets/kafka-cluster/config.nix` (40 lines) - Kafka fuzzable config spec.
5. `targets/etcd-cluster/config.nix` (11 lines) - etcd fuzzable config spec.
6. `targets/kafka-cluster/module.nix` (59 lines) - Kafka NixOS base module with per-node identity.
7. `targets/kafka-cluster/properties.nix` (118 lines) - Kafka properties and `_check()` usage.
8. `targets/kafka-cluster/test-script.py` (11 lines) - Kafka integration test entry script.
9. `targets/etcd-cluster/module.nix` (55 lines) - etcd NixOS base module with per-node identity.
10. `targets/etcd-cluster/properties.nix` (101 lines) - etcd properties and `_check()` usage.
11. `targets/etcd-cluster/test-script.py` (10 lines) - etcd integration test entry script.
12. `lib/orchestrate.nix` (128 lines) - seed derivation, fuzz→shrink→expand→merge→runner pipeline.
13. `lib/expand-topology.nix` (219 lines) - topology expansion to per-node VLAN configs and nodeRoles.
14. `lib/runner.nix` (86 lines) - property injection, `_check()` harness, report handling.
15. `lib/properties.nix` (62 lines) - property composition (`setup`/`check`).
16. `lib/fuzzer.nix` (87 lines) - deterministic seed-based resolver returning `{ result, choices }`.
17. `lib/combinators.nix` (232 lines) - list combinators, path hashing, choice indexing; `bool`, `range`, `oneOf`.
18. `lib/merge.nix` (55 lines) - three-layer merge with `mkForce` on fuzzed layers.
19. `topotestix/orchestrator.py` (607 lines) - CLI orchestration, target loading, run/shrink/inspect wiring.
20. `topotestix/targets.py` (102 lines) - reads `targets/default.nix` and exposes target metadata.
21. `topotestix/runner.py` (69 lines) - runner CLI helpers, property listing, composed-script preview.
22. `topotestix/cli.py` (199 lines) - CLI surface (`targets`, `orchestrator`, `runner`, `runs`, `tui`).
23. `topotestix/nix.py` (79 lines) - path/json/string helpers and `nix build/eval` wrappers.
24. `docs/architecture.md` (377 lines) - vocabulary: topology, per-role fuzzing, three-layer merge, reportNode.
25. `docs/pipeline.md` (590 lines) - pipeline examples and target authoring guidance.
26. `docs/plan.md` (173 lines) - implementation status; confirms current conventions.
27. `flake.nix` (75 lines) and `flake.lock` - pinned input revision.

## Key Code

### Target registry
`targets/default.nix:1-40`
```nix
kafka-cluster = {
  topologyTarget = ./topology/kafka-cluster.nix;
  configTarget = ./config/kafka-cluster.nix;
  baseModule = ./kafka-cluster/module.nix;
  testScript = ./kafka-cluster/test-script.py;
  properties = ./kafka-cluster/properties.nix;
  reportNode = "kafka1";
};
```

### Topology pattern
`targets/kafka-cluster/topology.nix:1-6`, `lib/expand-topology.nix:144-219`
```nix
{ lib, ... }:
{
  roles.kafka = [ 3 ];
  kafkaVlans = [ [ 1 ] ];
}
```
```nix
expandRole = roleName:
  let
    count = topology-map.roles.${roleName};
    vlanKey = "${roleName}Vlans";
    vlans = topology-map.${vlanKey} or [];
  in {
    configs = builtins.listToAttrs (lib.genList mkNode count);
    roles = builtins.listToAttrs (map (name: { inherit name; value = roleName; }) nodeNames);
  };
```

### Config-spec pattern
`targets/kafka-cluster/config.nix:4-39`, `targets/etcd-cluster/config.nix:4-10`, `lib/combinators.nix:146-232`
```nix
virtualisation.memorySize = [ 2048 3072 4096 ];
services.apache-kafka.settings."min.insync.replicas" = [ 1 2 ];
services.apache-kafka.settings."auto.create.topics.enable" = [ false true ];
```
```nix
bool = [ false true ];
resolve = prefix: value:
  resolveWithKeyPrefix "" prefix value;
```

### Module pattern / per-node identity
`targets/kafka-cluster/module.nix:1-58`, `targets/etcd-cluster/module.nix:1-54`
```nix
let
  nodeIds = { kafka1 = 1; kafka2 = 2; kafka3 = 3; };
  nodeId = nodeIds.${nodeName};
in {
  services.apache-kafka.settings."node.id" = nodeId;
  services.apache-kafka.settings."controller.quorum.voters" = "1@kafka1:9093,2@kafka2:9093,3@kafka3:9093";
}
```
```nix
services.etcd = {
  name = nodeName;
  initialCluster = [ "etcd1=http://etcd1:2380" ... ];
  initialClusterState = "new";
};
```

### Property / test-script pattern
`lib/runner.nix:29-85`, `targets/etcd-cluster/properties.nix:4-100`, `targets/etcd-cluster/test-script.py:1-10`
```nix
def _check(name, fn, *args, **kwargs):
  try:
    fn(*args, **kwargs)
    _report.append({"name": name, "status": "passed"})
  except Exception as e:
    _report.append({"name": name, "status": "failed", "message": str(e)})
```
```python
setup = ''
  def check_etcd_cluster_healthy(machine):
      machine.succeed("etcdctl endpoint health --cluster")
'';
check = ''
  _check("etcd-cluster-healthy-from-etcd1", check_etcd_cluster_healthy, etcd1)
'';
```

### Orchestrator / CLI integration
`topotestix/targets.py:46-64`, `topotestix/orchestrator.py:26-66`, `topotestix/runner.py:10-27`
```py
registry_path = resolve_path("targets/default.nix", project_root)
...
properties = toString target.properties
reportNode = target.reportNode or ""
```
```py
orchestrate {
  seed = 42;
  inherit topologyTarget configTarget baseModule testScript;
  properties = builtins.attrValues propertiesMod;
  reportNode = "kafka1";
}
```

## Architecture
- Discovery: Python loads `targets/default.nix` and converts paths to strings.
- Run path: `topotestix.orchestrator` builds a Nix expr that imports `lib/orchestrate.nix`.
- Pipeline: topology fuzzer → shrinker → `expandTopology` → per-role config fuzzer → merge → runner.
- Topology is role-count + role-VLAN lists; `expandTopology` emits `nodeConfigs` and `nodeRoles`.
- Base modules receive `nodeName` only; distinct roles are inferred from `nodeName`/`nodeRoles` and hard-coded mappings in the module.
- Runner injects property helpers into the Python test script, auto-appends `_check()` calls, then copies a JSON report from `reportNode`.

## Start Here
Open `targets/default.nix` first. It is the registry every new SUT must extend, and it points to the exact files the orchestrator/CLI will load.

## Constraints / risks / integration points for `postgresql`
- Create: `targets/postgresql/topology.nix`, `targets/postgresql/config.nix`, `targets/postgresql/module.nix`, `targets/postgresql/properties.nix`, `targets/postgresql/test-script.py`.
- Edit: `targets/default.nix` to register the new target; possibly docs/examples if target naming or topology conventions need updating.
- Topology support: current generator supports role counts (`roles.<role> = [ N ]`) and per-role VLAN lists (`<role>Vlans = [ [ ... ] ]`). It does **not** encode direct primary→standby relationships; any 1+1 vs 1+2 cascade choice must be represented as role counts plus module-level bootstrap logic.
- 1+1 vs 1+2: the existing topology layer can express either 1 primary + 1 standby or 1 primary + 2 standbys by choosing `roles.primary = [1]` and `roles.standby = [1]` or `[1 2]`; both roles share the same VLAN if they need replication traffic.
- Replication bootstrap: existing examples bootstrap cluster membership in the module (`etcd initialCluster`, Kafka quorum voters) and then use the test script for validation. No dedicated Postgres bootstrap helper exists in-tree.
- Report node: use the primary (`postgres1`) as `reportNode` unless you want a standby to report; current multi-node targets report from the first node (`kafka1`, `etcd1`).
- Open questions/TODOs: docs say per-role fuzzing is current behavior, `reportNode` defaults to first node if omitted, and topology choices are choice-index based (shrinkable). Search before editing for any PostgreSQL-specific TODOs; none were found.
- Nixpkgs pin: `flake.lock` pins `nixpkgs` to `cb2938ebeac96284932dbe6a2fb611d3b77743a5` (`lastModified` 1778331559).
