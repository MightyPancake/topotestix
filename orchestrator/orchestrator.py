#!/usr/bin/env python3
"""Compatibility wrapper for the TopoTestix CLI package."""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from topotestix.cli import main as topotestix_main
from topotestix.nix import build_test, eval_json, nix_json, nix_path, nix_string, resolve_path
from topotestix.orchestrator import (
    candidate_choice_maps,
    cmd_fuzz,
    cmd_run,
    cmd_shrink,
    generate_fuzz_expr,
    generate_nix_expr,
    generate_shrink_inputs_expr,
    parse_json_object,
    run_once,
)
from topotestix.reports import parse_report


def main() -> int:
    if len(sys.argv) > 1 and sys.argv[1] == "run":
        sys.argv = [sys.argv[0], "orchestrator", "run", "__legacy__"] + sys.argv[2:]
    elif len(sys.argv) > 1 and sys.argv[1] == "shrink":
        sys.argv = [sys.argv[0], "orchestrator", "shrink", "__legacy__"] + sys.argv[2:]
    elif len(sys.argv) > 1 and sys.argv[1] == "fuzz":
        args = sys.argv[2:]
        translated = []
        index = 0
        while index < len(args):
            if args[index] == "--target" and index + 1 < len(args):
                translated.extend(["--config-target", args[index + 1]])
                index += 2
            elif args[index].startswith("--target="):
                translated.append("--config-target=" + args[index].split("=", 1)[1])
                index += 1
            else:
                translated.append(args[index])
                index += 1
        sys.argv = [sys.argv[0], "orchestrator", "fuzz", "__legacy__"] + translated
    return topotestix_main(sys.argv[1:])


if __name__ == "__main__":
    raise SystemExit(main())
