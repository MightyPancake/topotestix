#!/usr/bin/env python3
"""TopoTestix Orchestrator — coordinates fuzzer, expandTopology, and runner.

Generates a Nix expression that calls lib/orchestrate.nix with the provided
parameters, then builds it with `nix build`. All Nix-type computation (fuzzer,
expandTopology, mkForce merge, runner) happens inside Nix — Python just
orchestrates the build and parses the result.

From the project root, with nix develop (which provides python3):
nix develop -c python3 orchestrator/orchestrator.py run \
  --seed 5 \
  --topology-target targets/topology/single-machine.nix \
  --config-target targets/config/nginx.nix \
  --base-module targets/nginx/module.nix \
  --test-script targets/nginx/test-script.py \
  --properties targets/nginx/properties.nix \
  --name nginx-test

To test a failing seed (nginx disabled):
nix develop -c python3 orchestrator/orchestrator.py run \
  --seed 1 \
  --topology-target targets/topology/single-machine.nix \
  --config-target targets/config/nginx.nix \
  --base-module targets/nginx/module.nix \
  --test-script targets/nginx/test-script.py \
  --properties targets/nginx/properties.nix \
  --name nginx-test-fail
"""

import argparse
import json
import os
import shlex
import subprocess
import sys
import tempfile
from typing import Optional


def resolve_path(path: str, project_root: str) -> str:
    """Resolve a path to absolute, relative to project_root if not already absolute."""
    if os.path.isabs(path):
        return path
    return os.path.normpath(os.path.join(os.path.abspath(project_root), path))


def nix_string(value: str) -> str:
    """Render a Nix string safely."""
    return json.dumps(value)


def nix_path(path: str) -> str:
    """Render an absolute filesystem path for Nix import/readFile."""
    return f"(builtins.toPath {nix_string(path)})"


def nix_json(value) -> str:
    """Pass structured data to Nix via JSON instead of raw attrset interpolation."""
    return f"(builtins.fromJSON {nix_string(json.dumps(value, sort_keys=True))})"


def parse_json_object(value: str, label: str) -> dict:
    try:
        parsed = json.loads(value)
    except json.JSONDecodeError as exc:
        raise argparse.ArgumentTypeError(f"{label} must be valid JSON: {exc}") from exc
    if not isinstance(parsed, dict):
        raise argparse.ArgumentTypeError(f"{label} must be a JSON object")
    return parsed


def generate_nix_expr(
    seed: int,
    topology_target_path: str,
    config_target_path: str,
    base_module_path: str,
    test_script_path: str,
    properties_path: str,
    name: str,
    project_root: str,
    topology_choices: Optional[dict] = None,
    config_choices: Optional[dict] = None,
) -> str:
    """Generate a Nix expression that calls orchestrate.nix."""
    abs_topology_target = resolve_path(topology_target_path, project_root)
    abs_config_target = resolve_path(config_target_path, project_root)
    abs_base_module = resolve_path(base_module_path, project_root)
    abs_test_script = resolve_path(test_script_path, project_root)
    abs_properties = resolve_path(properties_path, project_root)
    abs_lib = resolve_path("lib", project_root)
    abs_orchestrate = resolve_path("lib/orchestrate.nix", project_root)

    return f"""let
  nixpkgs = builtins.getFlake "nixpkgs";
  pkgs = nixpkgs.legacyPackages.x86_64-linux;
  lib = pkgs.lib;

  orchestrate = (import {nix_path(abs_orchestrate)} {{ inherit pkgs lib; testers = pkgs.testers; }}).orchestrate;

  topologyTarget = import {nix_path(abs_topology_target)} {{ inherit lib; }};
  configTarget = import {nix_path(abs_config_target)} {{ inherit lib; }};
  baseModule = import {nix_path(abs_base_module)};
  testScript = builtins.readFile {nix_path(abs_test_script)};
  propertiesMod = import {nix_path(abs_properties)} {{ inherit lib; }};
in
orchestrate {{
  seed = {seed};
  inherit topologyTarget configTarget baseModule testScript;
  properties = builtins.attrValues propertiesMod;
  name = {nix_string(name)};
  topologyChoices = {nix_json(topology_choices or {})};
  configChoices = {nix_json(config_choices or {})};
}}"""


def generate_shrink_inputs_expr(
    seed: int,
    topology_target_path: str,
    config_target_path: str,
    project_root: str,
) -> str:
    """Generate a Nix expression that returns initial fuzzer choice maps."""
    abs_topology_target = resolve_path(topology_target_path, project_root)
    abs_config_target = resolve_path(config_target_path, project_root)
    abs_fuzzer = resolve_path("lib/fuzzer.nix", project_root)
    abs_shrinker = resolve_path("lib/shrinker.nix", project_root)

    return f"""let
  nixpkgs = builtins.getFlake "nixpkgs";
  pkgs = nixpkgs.legacyPackages.x86_64-linux;
  lib = pkgs.lib;

  fuzzer = (import {nix_path(abs_fuzzer)} {{ inherit lib; }}).fuzzer;
  shrinker = import {nix_path(abs_shrinker)} {{ inherit lib; }};
  topologyTarget = import {nix_path(abs_topology_target)} {{ inherit lib; }};
  configTarget = import {nix_path(abs_config_target)} {{ inherit lib; }};

  fuzzedTopology = fuzzer {{ seed = {nix_string(str(seed))}; target = topologyTarget; }};
  topology = shrinker.apply topologyTarget fuzzedTopology.result {{}};
  roleNames = builtins.sort (a: b: a < b) (builtins.attrNames topology.roles);
  configChoices = builtins.listToAttrs (lib.imap0 (idx: roleName:
    let
      roleSeed = toString ({seed} + 1 + idx);
      fuzzedRole = fuzzer {{ seed = roleSeed; target = configTarget; }};
    in
    {{ name = roleName; value = fuzzedRole.choices; }}
  ) roleNames);
in
{{
  topologyChoices = fuzzedTopology.choices;
  inherit configChoices;
}}"""


def generate_fuzz_expr(seed: str, target_path: str, project_root: str) -> str:
    """Generate a Nix expression that evaluates the fuzzer for one target."""
    abs_target = resolve_path(target_path, project_root)
    abs_fuzzer = resolve_path("lib/fuzzer.nix", project_root)

    return f"""let
  nixpkgs = builtins.getFlake "nixpkgs";
  pkgs = nixpkgs.legacyPackages.x86_64-linux;
  lib = pkgs.lib;

  fuzzer = (import {nix_path(abs_fuzzer)} {{ inherit lib; }}).fuzzer;
  target = import {nix_path(abs_target)} {{ inherit lib; }};
in
fuzzer {{
  seed = {nix_string(seed)};
  inherit target;
}}"""


def build_test(nix_expr: str, output_link: str) -> subprocess.CompletedProcess:
    """Write the Nix expression to a temp file and build it with nix build."""
    with tempfile.NamedTemporaryFile(mode="w", suffix=".nix", delete=False) as f:
        f.write(nix_expr)
        f.flush()
        temp_path = f.name

    try:
        result = subprocess.run(
            [
                "nix", "build", "--impure",
                "--extra-experimental-features", "nix-command flakes",
                "--file", temp_path,
                "-o", output_link,
                "-L",
            ],
            capture_output=True,
            text=True,
        )
        return result
    finally:
        os.unlink(temp_path)


def parse_report(result_path: str) -> list[dict]:
    """Read and parse report.json from the build output."""
    report_path = os.path.join(result_path, "report.json")
    if not os.path.exists(report_path):
        return []
    with open(report_path) as f:
        return json.load(f)


def print_summary(seed: int, name: str, report: list[dict], build_ok: bool, result_path: str):
    """Print a summary of the test results."""
    print()
    print("=" * 60)
    print(f" TopoTestix Results")
    print(f" Seed: {seed}")
    print(f" Name: {name}")
    print("=" * 60)

    if not build_ok:
        print()
        print(" VM test FAILED (build error)")
        print(f" Result link: {result_path}")
        return

    if not report:
        print()
        print(" No report.json found")
        print(f" Result link: {result_path}")
        return

    print()
    for entry in report:
        status = entry.get("status", "unknown")
        name_str = entry.get("name", "unnamed")
        if status == "passed":
            print(f"  PASS  {name_str}")
        else:
            message = entry.get("message", "")
            print(f"  FAIL  {name_str}: {message}")

    all_passed = all(e.get("status") == "passed" for e in report)
    print()
    print(f" Overall: {'PASSED' if all_passed else 'FAILED'}")
    print(f" Result link: {result_path}")
    print("=" * 60)


def run_once(args, project_root: str, topology_choices: Optional[dict] = None, config_choices: Optional[dict] = None):
    nix_expr = generate_nix_expr(
        seed=args.seed,
        topology_target_path=args.topology_target,
        config_target_path=args.config_target,
        base_module_path=args.base_module,
        test_script_path=args.test_script,
        properties_path=args.properties,
        name=args.name,
        project_root=project_root,
        topology_choices=topology_choices,
        config_choices=config_choices,
    )

    result_link = os.path.join(project_root, f"result-{args.name}-seed-{args.seed}")

    print("Building NixOS VM test...")
    result = build_test(nix_expr, result_link)

    build_ok = result.returncode == 0

    if not build_ok:
        print(f"\nBuild failed. stderr:\n{result.stderr}", file=sys.stderr)

    report = parse_report(result_link)
    print_summary(args.seed, args.name, report, build_ok, result_link)

    passed = build_ok and bool(report) and all(e.get("status") == "passed" for e in report)
    return passed, report, result_link, result


def cmd_run(args):
    """Execute the run subcommand."""
    project_root = args.project_root or os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

    passed, _report, _result_link, _result = run_once(
        args,
        project_root,
        topology_choices=args.topology_choices,
        config_choices=args.config_choices,
    )

    if not passed:
        sys.exit(1)


def cmd_fuzz(args):
    """Execute the fuzz subcommand."""
    project_root = args.project_root or os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    result = eval_json(generate_fuzz_expr(args.seed, args.target, project_root))
    print(json.dumps(result, indent=2, sort_keys=True))


def eval_json(nix_expr: str) -> dict:
    result = subprocess.run(
        [
            "nix", "eval", "--json", "--impure",
            "--extra-experimental-features", "nix-command flakes",
            "--expr", nix_expr,
        ],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        raise RuntimeError(f"nix eval failed:\n{result.stderr}")
    return json.loads(result.stdout)


def candidate_choice_maps(choices: dict):
    """Yield choice maps that reduce one index while preserving all other choices."""
    for path in sorted(choices):
        current = choices[path]
        if not isinstance(current, int):
            continue
        for next_index in range(current - 1, -1, -1):
            candidate = dict(choices)
            candidate[path] = next_index
            yield path, next_index, candidate


def reproducible_command(args, topology_choices: dict, config_choices: dict) -> str:
    parts = [
        "python3", "orchestrator/orchestrator.py", "run",
        "--seed", str(args.seed),
        "--topology-target", args.topology_target,
        "--config-target", args.config_target,
        "--base-module", args.base_module,
        "--test-script", args.test_script,
        "--properties", args.properties,
        "--name", args.name,
        "--topology-choices", json.dumps(topology_choices, sort_keys=True),
        "--config-choices", json.dumps(config_choices, sort_keys=True),
    ]
    if args.project_root:
        parts.extend(["--project-root", args.project_root])
    return " ".join(shlex.quote(part) for part in parts)


def cmd_shrink(args):
    """Execute greedy choice-based shrinking for a failing seed."""
    project_root = args.project_root or os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    args.seed = args.master_seed

    inputs = eval_json(generate_shrink_inputs_expr(
        seed=args.seed,
        topology_target_path=args.topology_target,
        config_target_path=args.config_target,
        project_root=project_root,
    ))
    topology_choices = inputs["topologyChoices"]
    config_choices = inputs["configChoices"]

    print("Verifying initial failure before shrinking...")
    passed, _report, _result_link, _result = run_once(args, project_root, topology_choices, config_choices)
    if passed:
        print("Initial seed passed; nothing to shrink.", file=sys.stderr)
        sys.exit(1)

    changed = True
    while changed:
        changed = False

        for path, next_index, candidate in candidate_choice_maps(topology_choices):
            print(f"Trying topology shrink {path} -> {next_index}")
            passed, _report, _result_link, _result = run_once(args, project_root, candidate, config_choices)
            if not passed:
                topology_choices = candidate
                changed = True
                print(f"Kept topology shrink {path} -> {next_index}")
                break
        if changed:
            continue

        for role in sorted(config_choices):
            for path, next_index, candidate_role_choices in candidate_choice_maps(config_choices[role]):
                candidate_config_choices = dict(config_choices)
                candidate_config_choices[role] = candidate_role_choices
                print(f"Trying config shrink {role}{path} -> {next_index}")
                passed, _report, _result_link, _result = run_once(args, project_root, topology_choices, candidate_config_choices)
                if not passed:
                    config_choices = candidate_config_choices
                    changed = True
                    print(f"Kept config shrink {role}{path} -> {next_index}")
                    break
            if changed:
                break

    print()
    print("Final topology choices:")
    print(json.dumps(topology_choices, indent=2, sort_keys=True))
    print("Final config choices:")
    print(json.dumps(config_choices, indent=2, sort_keys=True))
    print("Reproduce with:")
    print(reproducible_command(args, topology_choices, config_choices))


def main():
    parser = argparse.ArgumentParser(description="TopoTestix Orchestrator")
    subparsers = parser.add_subparsers(dest="command")

    run_parser = subparsers.add_parser("run", help="Run a test with a given seed")
    run_parser.add_argument("--seed", type=int, default=1, help="Master seed (default: 1)")
    run_parser.add_argument("--topology-target", required=True, help="Path to topology target spec")
    run_parser.add_argument("--config-target", required=True, help="Path to config target spec")
    run_parser.add_argument("--base-module", required=True, help="Path to base NixOS module")
    run_parser.add_argument("--test-script", required=True, help="Path to Python test script")
    run_parser.add_argument("--properties", required=True, help="Path to properties module")
    run_parser.add_argument("--name", required=True, help="Test name")
    run_parser.add_argument("--project-root", default=None, help="Project root directory (auto-detected)")
    run_parser.add_argument("--topology-choices", type=lambda value: parse_json_object(value, "--topology-choices"), default={}, help="JSON object of topology shrink overrides")
    run_parser.add_argument("--config-choices", type=lambda value: parse_json_object(value, "--config-choices"), default={}, help="JSON object of per-role config shrink overrides")

    fuzz_parser = subparsers.add_parser("fuzz", help="Evaluate a fuzz target for one seed")
    fuzz_parser.add_argument("--seed", required=True, help="Fuzzer seed")
    fuzz_parser.add_argument("--target", required=True, help="Path to fuzz target spec")
    fuzz_parser.add_argument("--project-root", default=None, help="Project root directory (auto-detected)")

    shrink_parser = subparsers.add_parser("shrink", help="Shrink a failing seed")
    shrink_parser.add_argument("master_seed", type=int, help="Failing master seed to shrink")
    shrink_parser.add_argument("--topology-target", required=True, help="Path to topology target spec")
    shrink_parser.add_argument("--config-target", required=True, help="Path to config target spec")
    shrink_parser.add_argument("--base-module", required=True, help="Path to base NixOS module")
    shrink_parser.add_argument("--test-script", required=True, help="Path to Python test script")
    shrink_parser.add_argument("--properties", required=True, help="Path to properties module")
    shrink_parser.add_argument("--name", required=True, help="Test name")
    shrink_parser.add_argument("--project-root", default=None, help="Project root directory (auto-detected)")

    args = parser.parse_args()

    if args.command == "run":
        cmd_run(args)
    elif args.command == "fuzz":
        cmd_fuzz(args)
    elif args.command == "shrink":
        cmd_shrink(args)
    else:
        parser.print_help()
        sys.exit(1)


if __name__ == "__main__":
    main()
