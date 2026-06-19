# Nginx Orchestrator Test

End-to-end validation of the full TopoTestix orchestrator pipeline:
`orchestrator → fuzzer → expandTopology → merge → runner → NixOS VM test → report.json`

This replaces the manual `nginx/smoke-test` with a single command that drives the
entire pipeline through `lib/orchestrate.nix`.

## How it works

```
seed=5
    │
    ▼
fuzzer(seed, topologyTarget)  →  topology-map { roles.machine = 1, machineVlans = [1] }
    │
    ▼
expandTopology(topology-map)  →  { nodeConfigs: { machine1: { vlans: [1] } },
                                     nodeRoles: { machine1: "machine" } }
    │
    ▼
fuzzer(seed+1, configTarget)  →  fuzzedConfig (per-role, identical for all nodes of same role)
    │
    ▼
mergeConfigs(base, config=fuzzedConfig, topology=topologyConfig)  →  machine config (with mkForce)
    │
    ▼
runner.run(nodeConfigs, testScript, properties, name)  →  NixOS VM test derivation
    │
    ▼
nix build  →  VM boots, testScript runs, _check() evaluates properties, report.json written
    │
    ▼
result/report.json  →  [{"name": "nginx-responds-to-http", "status": "passed"}]
```

### Key difference from nginx/smoke-test

The smoke test manually wires up fuzzer → merge → runner in a temp Nix file.
This experiment uses `lib/orchestrate.nix` which handles the full pipeline including
topology expansion and per-role seed derivation.

Node names use indexed naming (`machine1` instead of `machine`) because
expandTopology always appends a 1-based index.

### Topology

Uses `targets/nginx/topology.nix` — a trivial topology that produces
a single `machine1` node on VLAN 1. This is the simplest possible topology.

## Running

```bash
cd experiments/nginx/orchestrator-test
./run-orchestrator-test.sh          # default seed 5 (nginx enabled, should pass)
./run-orchestrator-test.sh 1        # seed 1 (may disable nginx, expect failure)
./run-orchestrator-test.sh 5        # seed 5 (nginx enabled, should pass)
```

Or use the orchestrator CLI directly:

```bash
python3 orchestrator/orchestrator.py run \
  --seed 5 \
  --topology-target targets/nginx/topology.nix \
  --config-target targets/nginx/config.nix \
  --base-module targets/nginx/module.nix \
  --test-script targets/nginx/test-script.py \
  --properties targets/nginx/properties.nix \
  --name nginx-orchestrator
```