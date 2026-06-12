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

## Phase 4: Shrinking

- [x] Update `lib/combinators.nix` — change `bool` from `[true false]` to `[false true]` (false is simpler, lower index = simpler)
- [x] Update `lib/combinators.nix` — `resolve` now returns `{ value, choices }` instead of just the resolved value
- [x] Update fuzzer to return `{ result, choices }` — choices maps path strings to indices
- [x] Create `lib/shrinker.nix` — pure Nix shrinking module (see [shrinking.md](shrinking.md))
- [x] Create shrinker tests (`tests/shrinker-test.nix`)
- [x] Update `lib/orchestrate.nix` — add `topologyChoices` and `configChoices` parameters, pass through shrinker
- [x] Update `orchestrator/orchestrator.py` — add `--shrink <master_seed>` mode, shrinking loop, `--topology-choices`/`--config-choices` for `run`
- [x] End-to-end shrinking verification with nginx SUT

## Phase 4.1: Fuzzer/Shrinker Contract Fix

- [x] Change fuzzer choices to target-relative paths like `.virtualisation.memorySize` and `.roles.machine`
- [x] Keep the seed only in the hash key used for deterministic value selection, not in the public choices map
- [x] Update fuzzer and shrinker docs to describe the target-relative choices contract
- [x] Update existing fuzzer/combinator tests affected by the choices path change

## Phase 4.2: Cross-Module Shrinking Tests

- [x] Add tests proving `fuzzer.choices` keys are directly usable with `shrinker.apply`
- [x] Add config pipeline tests for `fuzzer -> shrinker`
- [x] Add topology pipeline tests for `fuzzer -> shrinker -> expandTopology`
- [x] Add tests that every `fuzzer.choices` key exists in `shrinker.choicePaths target`

## Phase 4.3: Python Shrink CLI

- [x] Implement real `orchestrator.py --shrink` support
- [x] Add `--topology-choices` and `--config-choices` to `run` for reproducing shrunk cases
- [x] Print final reproducible command and override maps after shrinking
- [x] Add Python tests for argument parsing and generated shrink inputs where practical

## Phase 4.4: Python/Nix Boundary Hardening

- [x] Explore safer alternatives to raw Python-generated Nix string interpolation
- [x] Escape Nix strings safely, especially `name`
- [x] Render paths safely, including paths with spaces or special characters
- [x] Consider passing structured values through JSON (`builtins.fromJSON`) or generated parameter files
- [x] Add tests for generated Nix expressions with unusual names and paths

## Phase 4.5: Merge Safety

- [x] Explore alternatives to blindly recursing through every attrset in `mkForceAttrs`
- [x] Treat module/meta attrsets such as `_type`, `mkIf`, `mkMerge`, and derivation-like values carefully
- [x] Add merge tests for special attrsets before changing behavior
- [x] Pick the smallest safe merge behavior that preserves fuzzed option priority

## Phase 4.6: Validation Safeguards

- [x] Add clear errors for empty choice lists
- [x] Validate `range` inputs (`step = 0`, incompatible bounds, invalid direction)
- [x] Add clear errors for invalid shrinker paths
- [x] Add clear errors for out-of-range shrinker indices
- [x] Add tests for invalid combinator and shrinker inputs

## Phase 4.7: Current-Behavior Documentation Cleanup

- [x] Update docs to say config fuzzing is currently per-role, not per-node
- [x] Update docs to say property checks are currently auto-appended; explicit checkpoints are future work
- [x] Remove `nodeCount` from docs/examples unless it becomes enforced by `expandTopology`
- [x] Remove or mark unimplemented `dependent` combinator references as future work
- [x] Fix stale comments in `lib/properties.nix`

## Phase 4.8: Library Export Cleanup

- [x] Export `runner` and `orchestrate` from `lib/default.nix`, or document why they are intentionally imported directly
- [x] Keep import interfaces clean for modules that require `pkgs` and `testers`

## Phase 4.9: Repository Cleanup

- [x] Archive `experiments/` under docs or clearly mark it as historical/non-production material
- [x] Add a short README for archived experiments explaining their status
- [x] Add minimal CI that runs `nix flake check`
- [x] Add Python formatting/linting setup if `orchestrator.py` grows during shrink implementation

## Phase 5: Real SUT

- [x] Kafka SUT targets (single-node and multi-node base modules, properties, test scripts, config targets)

## Phase 6: Text User Interface

- [x] fuzzer CLI
- [x] Python package foundation with `topotestix` executable
- [x] Nix target registry (`targets/default.nix`) as the source of truth for named SUT targets
- [x] Target discovery CLI (`topotestix targets list/show`)
- [x] Docker-like orchestrator CLI (`topotestix orchestrator run/fuzz/shrink/sweep`)
- [x] Persistent run store under `.topotestix/runs`
- [x] Run history CLI (`topotestix runs list/show/logs/report`)
- [x] Practical runner CLI (`topotestix runner compose-script/inspect-report/show-properties`)
- [x] Event-based execution model for CLI progress and TUI rendering
- [x] Initial Textual TUI execution mode (`topotestix tui TARGET --seeds ...`)
- [x] Compatibility wrapper for existing `orchestrator/orchestrator.py` commands

## Phase 7: Scale

- [ ] orchestrator multi-execution

## Phase 8: Extra Features

- [ ] failure-reproducing flake
- [ ] fuzzing regular nixos configurations (auto-resolving option variants from NixOS documentation so users only need to point at a configuration and specify which options to fuzz)
- [ ] runner as http service
- [ ] selective property inclusion via `--property-name` CLI flag
- [ ] choice-based shrinking (manipulate generated config values via index-based overrides, see [shrinking.md](shrinking.md))
- [ ] inject other host names to /etc/hosts to posibility to pinging by hostname
- [ ] NixOS default values as minimal baseline (requires querying NixOS module system)
- [ ] weighted shrinking toward error-prone configs (less memory → more OOM, fewer nodes → quorum loss)
- [ ] shrinking choices separete for each role

## Notes

- Fuzzer is pure: `seed + target → { result, choices }`. No cluster logic, no node naming. `result` is the flat attrset; `choices` maps path strings to indices.
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
- `composedProps.check` is currently auto-appended after the user test script; explicit checkpoints are future work
- Simple SUT (nginx) validates the pipeline end-to-end before bringing in Kafka's long build times
- Smoke test is manual: run a single seed through fuzzer → merge → runner, verify report.json output
- Phase 2 shrinking: not in scope. Phase 4 adds choice-based shrinking — the shrinker module reduces option indices toward 0 (lower index = simpler value). See [shrinking.md](shrinking.md).
- Shrinking approach: choice-based (not seed-based). The fuzzer returns `{ result, choices }` where choices maps paths to indices. The shrinker replaces specific indices with lower ones. Python orchestrator drives the iterative shrinking loop. See [shrinking.md](shrinking.md).
- Phase 2 always requires `--topology-target` — no single-node mode. Single-node tests use a trivial topology like `single-machine.nix`.
- Orchestrator starts as single orchestrator.py with argparse; later packaged as Nix-managed Python package (pyproject.toml)
- Nix testing via nix-unit (test attributes prefixed with `test`, expr/expected format)
- Kafka SUT (Phase 5) replaces the nginx SUT only after shrinking is proven on the fast nginx pipeline.
- Python ↔ Nix interface: orchestrator generates temp `.nix` file, calls `nix build --impure --file`. All Nix-type computation stays in Nix. `nix eval --json` used for shrinking two-pass approach (Phase 4).
- Runner is a Nix function, not a Python module — it composes testScript and calls `testers.runNixOSTest`
- `reportNode` defaults to first node in `nodeConfigs`, configurable for multi-node tests
