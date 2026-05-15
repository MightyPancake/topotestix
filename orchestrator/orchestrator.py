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
import subprocess
import sys
import tempfile


def resolve_path(path: str, project_root: str) -> str:
    """Resolve a path to absolute, relative to project_root if not already absolute."""
    if os.path.isabs(path):
        return path
    return os.path.normpath(os.path.join(project_root, path))


def generate_nix_expr(
    seed: int,
    topology_target_path: str,
    config_target_path: str,
    base_module_path: str,
    test_script_path: str,
    properties_path: str,
    name: str,
    project_root: str,
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

  orchestrate = (import {abs_orchestrate} {{ inherit pkgs lib; testers = pkgs.testers; }}).orchestrate;

  topologyTarget = import {abs_topology_target} {{ inherit lib; }};
  configTarget = import {abs_config_target} {{ inherit lib; }};
  baseModule = import {abs_base_module};
  testScript = builtins.readFile {abs_test_script};
  propertiesMod = import {abs_properties} {{ inherit lib; }};
in
orchestrate {{
  seed = {seed};
  inherit topologyTarget configTarget baseModule testScript;
  properties = builtins.attrValues propertiesMod;
  name = "{name}";
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


def cmd_run(args):
    """Execute the run subcommand."""
    project_root = args.project_root or os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

    nix_expr = generate_nix_expr(
        seed=args.seed,
        topology_target_path=args.topology_target,
        config_target_path=args.config_target,
        base_module_path=args.base_module,
        test_script_path=args.test_script,
        properties_path=args.properties,
        name=args.name,
        project_root=project_root,
    )

    result_link = os.path.join(project_root, f"result-{args.name}-seed-{args.seed}")

    print("Building NixOS VM test...")
    result = build_test(nix_expr, result_link)

    build_ok = result.returncode == 0

    if not build_ok:
        print(f"\nBuild failed. stderr:\n{result.stderr}", file=sys.stderr)

    report = parse_report(result_link)
    print_summary(args.seed, args.name, report, build_ok, result_link)

    if not build_ok or not all(e.get("status") == "passed" for e in report):
        sys.exit(1)


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

    args = parser.parse_args()

    if args.command == "run":
        cmd_run(args)
    else:
        parser.print_help()
        sys.exit(1)


if __name__ == "__main__":
    main()
