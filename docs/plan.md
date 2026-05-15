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

- [x] `lib/orchestrate.nix` — full pipeline function (fuzzer → expandTopology → merge → runner)
- [x] Update `lib/expand-topology.nix` — return `{ nodeConfigs, nodeRoles }` instead of just node attrset
- [x] Update expand-topology tests for new output structure
- [x] Rewrite `orchestrator/orchestrator.py` — CLI with `run` subcommand, single-seed execution
- [x] Create `targets/topology/single-machine.nix` — trivial topology for single-node tests
- [x] Update `targets/nginx/test-script.py` — `machine` → `machine1`
- [x] Update `targets/nginx/properties.nix` — `machine` → `machine1`
- [x] End-to-end verification with nginx smoke test via orchestrator

## Phase 3: Topology

- [x] topology target spec (VLAN sets per role, node count, role counts) — exists as `targets/topology/simple-cluster.nix`
- [x] expandTopology function (topology-map → per-node VLAN configs, deterministic, no seed) — exists as `lib/expand-topology.nix`
- [x] expandTopology tests (unit tests for expansion logic + nodeRoles output)
- [x] orchestrator integration (fuzzer call for topology + expandTopology + per-role fuzzer calls) — done in Phase 2

## Phase 4: Real SUT

- [ ] Kafka SUT target (replace simple SUT)

## Phase 5: Text User Interface

- [ ] fuzzer CLI
- [ ] runner CLI
- [ ] orchestrator CLI & TUI

## Phase 6: Shrinking

- [ ] Two-pass shrinking approach: (1) `nix eval` topology to learn structure, (2) build full test with specific seeds
- [ ] Per-dimension seed shrinking: try smaller seeds per dimension (topology, per-role config) independently
- [ ] Orchestrator prints seed map for reproduction

## Phase 7: Scale

- [ ] orchestrator multi-execution

## Phase 8: Extra Features

- [ ] failure-reproducing flake
- [ ] fuzzing regular nixos configurations (auto-resolving option variants from NixOS documentation so users only need to point at a configuration and specify which options to fuzz)
- [ ] runner as http service
- [ ] selective property inclusion via `--property-name` CLI flag
- [ ] value-based shrinking (manipulate generated config values directly, requires fuzzer per-path overrides)
- [ ] inject other host names to /etc/hosts to posibility to pinging by hostname

## Notes

- Fuzzer is pure: `seed + target → flat attrset`. No cluster logic, no node naming.
- expandTopology is a separate pure function: `topology-map → per-node VLAN configs`. No seed, no randomness.
- Merge module is in `lib/merge.nix`, separate from runner — same pattern as `expand-topology.nix` being separate from fuzzer. Merge is an orchestration concern, not a runner concern.
- Orchestrator derives all seeds from master_seed: `master_seed + 0` for topology, `master_seed + 1 + roleIndex` for per-role config (alphabetical role order). All nodes of the same role share one fuzzer call.
- Node naming: always indexed (e.g., `broker1`, `machine1`). No conditional naming — count=1 still gets index.
- expandTopology returns `{ nodeConfigs, nodeRoles }` — `nodeRoles` maps node names to role names for per-role config lookup.
- Orchestrator has two layers: `lib/orchestrate.nix` (pipeline logic, testable with nix-unit) and `orchestrator/orchestrator.py` (CLI wrapper, generates temp Nix expression, calls nix build).
- Properties: include all from module via `builtins.attrValues`. Selective inclusion is a future addition.
- Three-layer merge happens inside each node's module function (where `pkgs` is in scope).
- Python generates a temp `.nix` file and runs `nix build --impure --file tempfile.nix` — same approach as `run-smoke-test.sh`.
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
- Phase 2 shrinking: not in scope. Phase 6 will add per-dimension seed shrinking (move the seed, keep structure fixed). Future: value-based shrinking (move the values, keep seed fixed).
- Phase 2 always requires `--topology-target` — no single-node mode. Single-node tests use a trivial topology like `single-machine.nix`.
- Orchestrator starts as single orchestrator.py with argparse; later packaged as Nix-managed Python package (pyproject.toml)
- Nix testing via nix-unit (test attributes prefixed with `test`, expr/expected format)
- Python ↔ Nix interface: orchestrator generates temp `.nix` file, calls `nix build --impure --file`. All Nix-type computation stays in Nix. `nix eval --json` used for shrinking two-pass approach (Phase 6).
- Runner is a Nix function, not a Python module — it composes testScript and calls `testers.runNixOSTest`
- `reportNode` defaults to first node in `nodeConfigs`, configurable for multi-node tests
