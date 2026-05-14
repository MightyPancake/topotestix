# TopoTestix Implementation Plan

## Phase 1: Foundation

- [x] combinators library + tests
- [x] fuzzer (seed + target → flat attrset, pure function, no cluster logic)
- [x] fuzzer tests
- [x] properties framework (minimal, just the injection mechanism)
- [x] merge module (`lib/merge.nix`) — `mkForceAttrs` and `mergeConfigs` (separate from runner, same pattern as expand-topology being separate from fuzzer)
- [x] merge module tests
- [x] runner (`lib/runner.nix`) — `composeTestScript` and `run`
- [x] runner tests - test script correctness
- [x] nginx SUT target update (test-script.py uses `_check()`, properties wired)
- [x] end-to-end smoke test (flake.nix: fuzzer → merge → runner → build → report.json)

## Phase 2: Orchestration (basic)

- [ ] orchestrator minimal (single seed, seed derivation, three-layer merge)

## Phase 3: Topology

- [ ] topology target spec (VLAN sets per role, node count, role counts)
- [ ] expandTopology function (topology-map → per-node VLAN configs, deterministic, no seed)
- [ ] expandTopology tests (unit tests for expansion logic)
- [ ] orchestrator integration (fuzzer call for topology + expandTopology + per-node fuzzer calls)

## Phase 4: Real SUT

- [ ] Kafka SUT target (replace simple SUT)

## Phase 5: Text User Interface

- [ ] fuzzer CLI
- [ ] runner CLI
- [ ] orchestrator CLI & TUI

## Phase 6: Shrinking

- [ ] orchestrator shrinking

## Phase 7: Scale

- [ ] orchestrator multi-execution

## Phase 8: Extra Features

- [ ] failure-reproducing flake
- [ ] fuzzing regular nixos configurations (auto-resolving option variants from NixOS documentation so users only need to point at a configuration and specify which options to fuzz)
- [ ] runner as http service

## Notes

- Fuzzer is pure: `seed + target → flat attrset`. No cluster logic, no node naming.
- expandTopology is a separate pure function: `topology-map → per-node VLAN configs`. No seed, no randomness.
- Merge module is in `lib/merge.nix`, separate from runner — same pattern as `expand-topology.nix` being separate from fuzzer. Merge is an orchestration concern, not a runner concern.
- Orchestrator derives all seeds from master_seed: `master_seed + 0` for topology, `master_seed + 1..N` for per-node config.
- Three-layer config composition: base ⊕ fuzzed target configs ⊕ fuzzed topology configs — merge module handles this with mkForce on fuzzed layers only
- VLAN membership is per-node lists (`virtualisation.vlans = [1 10]`), enabling mixed topologies and partitions
- Combinators come first because the fuzzer depends on them
- Properties framework is minimal at first — just the injection mechanism into testScript
- Runner composes testScript: harness preamble → property setup → user testScript → explicit `_check()` calls → report writing → assertion on failures
- `_check()` catches all exceptions and does NOT re-raise — all properties always get evaluated
- Report written via `copy_from_machine` to `$out/report.json`; JSON encoded as base64 to avoid shell escaping
- `composedProps.check` NOT auto-appended — user places `_check()` calls explicitly (explicit checkpoints)
- Simple SUT (nginx) validates the pipeline end-to-end before bringing in Kafka's long build times
- Smoke test is manual: run a single seed through fuzzer → merge → runner, verify report.json output
- Kafka replaces the simple SUT only after the pipeline is proven
- Orchestrator starts as single orchestrator.py with argparse; later packaged as Nix-managed Python package (pyproject.toml)
- Nix testing via nix-unit (test attributes prefixed with `test`, expr/expected format)
- Python ↔ Nix interface: `nix eval --json` for fuzzer and expandTopology calls
- Runner is a Nix function, not a Python module — it composes testScript and calls `testers.runNixOSTest`
- `reportNode` defaults to first node in `nodeConfigs`, configurable for multi-node tests
