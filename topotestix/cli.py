import argparse
import json
import os
import sys
from typing import Optional

from .orchestrator import (
    cmd_fuzz,
    cmd_run,
    cmd_shrink,
    cmd_sweep,
    parse_json_object,
)
from .run_store import RunStore, default_runs_dir
from .runner import cmd_compose_script, cmd_inspect_report, cmd_show_properties
from .targets import print_target, print_targets, project_root_from_args
from .tui import cmd_tui


def add_common_target_overrides(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--topology-target", default=None, help="Override topology target path")
    parser.add_argument("--config-target", default=None, help="Override config target path")
    parser.add_argument("--base-module", default=None, help="Override base module path")
    parser.add_argument("--test-script", default=None, help="Override test script path")
    parser.add_argument("--properties", default=None, help="Override properties module path")


def add_run_common(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--project-root", default=argparse.SUPPRESS, help="Project root directory")
    parser.add_argument("--output-dir", default=None, help="Run store directory")
    parser.add_argument("--name", default=None, help="Run name")
    parser.add_argument("--json", action="store_true", help="Print JSON output")
    parser.add_argument("--quiet", action="store_true", help="Suppress human summary")
    parser.add_argument("--verbose", action="store_true", help="Print verbose diagnostics")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="topotestix", description="TopoTestix CLI")
    parser.add_argument("--project-root", default=None, help="Project root directory")
    subparsers = parser.add_subparsers(dest="command", required=True)

    targets = subparsers.add_parser("targets", help="Inspect target registry")
    target_sub = targets.add_subparsers(dest="targets_command", required=True)
    targets_list = target_sub.add_parser("list", help="List targets")
    targets_list.add_argument("--project-root", default=argparse.SUPPRESS)
    targets_list.add_argument("--json", action="store_true")
    targets_show = target_sub.add_parser("show", help="Show one target")
    targets_show.add_argument("target")
    targets_show.add_argument("--project-root", default=argparse.SUPPRESS)
    targets_show.add_argument("--json", action="store_true")

    orchestrator = subparsers.add_parser("orchestrator", help="Run fuzzed NixOS tests")
    orch_sub = orchestrator.add_subparsers(dest="orchestrator_command", required=True)

    run = orch_sub.add_parser("run", help="Run one seed")
    run.add_argument("target")
    run.add_argument("--seed", type=int, default=1)
    run.add_argument("--topology-choices", type=lambda value: parse_json_object(value, "--topology-choices"), default={})
    run.add_argument("--config-choices", type=lambda value: parse_json_object(value, "--config-choices"), default={})
    add_run_common(run)
    add_common_target_overrides(run)

    fuzz = orch_sub.add_parser("fuzz", help="Evaluate config fuzz target for one seed")
    fuzz.add_argument("target")
    fuzz.add_argument("--seed", required=True)
    add_run_common(fuzz)
    add_common_target_overrides(fuzz)

    shrink = orch_sub.add_parser("shrink", help="Shrink a failing seed")
    shrink.add_argument("target")
    shrink.add_argument("seed", type=int)
    add_run_common(shrink)
    add_common_target_overrides(shrink)

    sweep = orch_sub.add_parser("sweep", help="Run a range of seeds")
    sweep.add_argument("target")
    sweep.add_argument("--seeds", required=True, help="Seed range like 1..100 or comma list")
    sweep.add_argument("--fail-fast", action="store_true")
    add_run_common(sweep)
    add_common_target_overrides(sweep)

    runner = subparsers.add_parser("runner", help="Inspect runner outputs")
    runner_sub = runner.add_subparsers(dest="runner_command", required=True)
    compose = runner_sub.add_parser("compose-script", help="Print composed test script")
    compose.add_argument("target")
    compose.add_argument("--project-root", default=argparse.SUPPRESS)
    inspect = runner_sub.add_parser("inspect-report", help="Inspect a report path or run id")
    inspect.add_argument("path_or_run_id")
    inspect.add_argument("--project-root", default=argparse.SUPPRESS)
    inspect.add_argument("--json", action="store_true")
    props = runner_sub.add_parser("show-properties", help="List target property names")
    props.add_argument("target")
    props.add_argument("--project-root", default=argparse.SUPPRESS)
    props.add_argument("--json", action="store_true")

    runs = subparsers.add_parser("runs", help="Inspect run history")
    runs_sub = runs.add_subparsers(dest="runs_command", required=True)
    runs_list = runs_sub.add_parser("list", help="List runs")
    runs_list.add_argument("--project-root", default=argparse.SUPPRESS)
    runs_list.add_argument("--output-dir", default=None)
    runs_list.add_argument("--json", action="store_true")
    runs_show = runs_sub.add_parser("show", help="Show run metadata")
    runs_show.add_argument("run_id")
    runs_show.add_argument("--project-root", default=argparse.SUPPRESS)
    runs_show.add_argument("--output-dir", default=None)
    runs_logs = runs_sub.add_parser("logs", help="Print run logs")
    runs_logs.add_argument("run_id")
    runs_logs.add_argument("--project-root", default=argparse.SUPPRESS)
    runs_logs.add_argument("--output-dir", default=None)
    runs_logs.add_argument("--stderr", action="store_true")
    runs_report = runs_sub.add_parser("report", help="Print run report")
    runs_report.add_argument("run_id")
    runs_report.add_argument("--project-root", default=argparse.SUPPRESS)
    runs_report.add_argument("--output-dir", default=None)

    tui = subparsers.add_parser("tui", help="Run the Textual TUI")
    tui.add_argument("target")
    tui.add_argument("--seeds", default="1")
    tui.add_argument("--project-root", default=argparse.SUPPRESS)
    tui.add_argument("--output-dir", default=None)
    tui.add_argument("--name", default=None)
    add_common_target_overrides(tui)

    return parser


def runs_dir(project_root: str) -> str:
    return default_runs_dir(project_root)


def cmd_runs(args, project_root: str) -> int:
    store = RunStore(args.output_dir or runs_dir(project_root))
    if args.runs_command == "list":
        runs = store.list_runs()
        if args.json:
            print(json.dumps(runs, indent=2, sort_keys=True))
        else:
            for run in runs:
                print(f"{run['id']}\t{run.get('status')}\t{run.get('target')}\tseed={run.get('seed')}")
        return 0
    run_dir = store.resolve_run(args.run_id)
    if args.runs_command == "show":
        with open(os.path.join(run_dir, "run.json")) as f:
            print(json.dumps(json.load(f), indent=2, sort_keys=True))
    elif args.runs_command == "logs":
        filename = "stderr.log" if args.stderr else "stdout.log"
        with open(os.path.join(run_dir, filename)) as f:
            print(f.read(), end="")
    elif args.runs_command == "report":
        with open(os.path.join(run_dir, "report.json")) as f:
            print(json.dumps(json.load(f), indent=2, sort_keys=True))
    return 0


def main(argv: Optional[list[str]] = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    project_root = project_root_from_args(getattr(args, "project_root", None))
    try:
        if args.command == "targets":
            if args.targets_command == "list":
                print_targets(project_root, args.json)
            else:
                print_target(project_root, args.target, args.json)
            return 0
        if args.command == "orchestrator":
            if args.orchestrator_command == "run":
                return cmd_run(args, project_root)
            if args.orchestrator_command == "fuzz":
                return cmd_fuzz(args, project_root)
            if args.orchestrator_command == "shrink":
                return cmd_shrink(args, project_root)
            if args.orchestrator_command == "sweep":
                return cmd_sweep(args, project_root)
        if args.command == "runner":
            if args.runner_command == "compose-script":
                return cmd_compose_script(args, project_root)
            if args.runner_command == "inspect-report":
                return cmd_inspect_report(args, project_root)
            if args.runner_command == "show-properties":
                return cmd_show_properties(args, project_root)
        if args.command == "runs":
            return cmd_runs(args, project_root)
        if args.command == "tui":
            return cmd_tui(args, project_root)
    except (RuntimeError, ValueError, FileNotFoundError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2
    parser.print_help()
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
