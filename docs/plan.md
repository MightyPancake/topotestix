# TopoTestix Implementation Plan

## Phase 1: Foundation

- [ ] combinators library + tests
- [ ] fuzzer (seed + target → flat attrset, pure function, no cluster logic)
- [ ] fuzzer CLI + tests
- [ ] properties framework (minimal, just the injection mechanism)
- [ ] runner
- [ ] runner CLI
- [ ] runner tests
- [ ] simple SUT target (nginx or trivial service)
- [ ] end-to-end smoke test (manual single seed: fuzzer → runner → report)

## Phase 2: Orchestration (basic)

- [ ] orchestrator minimal (single seed, seed derivation, three-layer merge)

## Phase 3: Topology

- [ ] topology target spec (VLAN sets per role, node count, role counts)
- [ ] expandTopology function (topology-map → per-node VLAN configs, deterministic, no seed)
- [ ] expandTopology tests (unit tests for expansion logic)
- [ ] orchestrator integration (fuzzer call for topology + expandTopology + per-node fuzzer calls)

## Phase 4: Real SUT

- [ ] Kafka SUT target (replace simple SUT)

## Phase 5: Shrinking

- [ ] orchestrator shrinking

## Phase 6: Scale

- [ ] orchestrator multi-execution

## Notes

- Fuzzer is pure: `seed + target → flat attrset`. No cluster logic, no node naming.
- expandTopology is a separate pure function: `topology-map → per-node VLAN configs`. No seed, no randomness.
- Orchestrator derives all seeds from master_seed: `master_seed + 0` for topology, `master_seed + 1..N` for per-node config.
- Three-layer config composition: base ⊕ fuzzed target configs ⊕ fuzzed topology configs
- VLAN membership is per-node lists (`virtualisation.vlans = [1 10]`), enabling mixed topologies and partitions
- Combinators come first because the fuzzer depends on them
- Properties framework is minimal at first — just the injection mechanism into testScript
- Simple SUT (nginx) validates the pipeline end-to-end before bringing in Kafka's long build times
- Smoke test is manual: run a single seed through fuzzer → runner, verify report output
- Kafka replaces the simple SUT only after the pipeline is proven
- Orchestrator starts as single orchestrator.py with argparse; later packaged as Nix-managed Python package (pyproject.toml)
- Nix testing via nix-unit (test attributes prefixed with `test`, expr/expected format)
- Python ↔ Nix interface: `nix eval --json` for fuzzer and expandTopology calls
