"""Tests for sweep --resume and sweep --json.

These tests are unit-level: they exercise `find_existing_seeds` directly, and
drive `sweep_events` and `cmd_sweep` with a mocked `run_once` so no `nix build`
is ever invoked. The end-to-end behaviour of a real sweep over 50 seeds is
covered by the thesis evaluation run, not by these tests.
"""

import argparse
import io
import json
import os
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from dataclasses import dataclass
from typing import Optional
from unittest.mock import patch

# Make the topotestix package importable when running from the repo root.
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from topotestix.orchestrator import cmd_sweep, find_existing_seeds, sweep_events
from topotestix.run_store import RunStore
from topotestix.targets import Target


@dataclass
class _StubResult:
    returncode: int = 0
    stdout: str = ""
    stderr: str = ""


def _make_target(name: str = "kafka-cluster") -> Target:
    return Target(
        name=name,
        description="test target",
        topology_target="/dev/null/topo.nix",
        config_target="/dev/null/config.nix",
        base_module="/dev/null/module.nix",
        test_script="/dev/null/test-script.py",
        properties="/dev/null/properties.nix",
        report_node="node1",
    )


def _make_args(
    seeds: str,
    *,
    resume: bool = False,
    json_mode: bool = False,
    quiet: bool = False,
    name: Optional[str] = None,
    output_dir: Optional[str] = None,
    fail_fast: bool = False,
) -> argparse.Namespace:
    return argparse.Namespace(
        target="kafka-cluster",
        seeds=seeds,
        resume=resume,
        json=json_mode,
        quiet=quiet,
        name=name,
        output_dir=output_dir,
        fail_fast=fail_fast,
        topology_target=None,
        config_target=None,
        base_module=None,
        test_script=None,
        properties=None,
        project_root=os.getcwd(),
    )


def _record_completed_run(store: RunStore, target_name: str, seed: int, status: str = "passed") -> None:
    run = store.create_run(target_name, seed, f"{target_name}-seed-{seed}")
    store.write_json(
        run["dir"],
        "run.json",
        {
            "id": run["id"],
            "target": target_name,
            "seed": seed,
            "status": status,
            "summary": {"passed": 1 if status == "passed" else 0, "failed": 0 if status == "passed" else 1, "total": 1},
        },
    )


# --- find_existing_seeds ----------------------------------------------------


class FindExistingSeedsTests(unittest.TestCase):
    def test_returns_seeds_with_completed_run_for_target(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            store = RunStore(tmpdir)
            for seed in (3, 7):
                _record_completed_run(store, "kafka-cluster", seed)
            target = _make_target("kafka-cluster")
            self.assertEqual(find_existing_seeds(store, target, [3, 4, 5, 6, 7]), {3, 7})

    def test_ignores_runs_for_other_targets(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            store = RunStore(tmpdir)
            _record_completed_run(store, "nginx", 3)
            target = _make_target("kafka-cluster")
            self.assertEqual(find_existing_seeds(store, target, [3, 4]), set())

    def test_empty_when_no_runs(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            store = RunStore(tmpdir)
            target = _make_target("kafka-cluster")
            self.assertEqual(find_existing_seeds(store, target, [1, 2, 3]), set())

    def test_only_returns_seeds_in_query_set(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            store = RunStore(tmpdir)
            _record_completed_run(store, "kafka-cluster", 3)
            _record_completed_run(store, "kafka-cluster", 99)
            target = _make_target("kafka-cluster")
            self.assertEqual(find_existing_seeds(store, target, [1, 2, 3]), {3})

    def test_includes_failed_runs(self):
        # --resume skips both passed and failed runs; user must delete
        # the run dir to force a re-run.
        with tempfile.TemporaryDirectory() as tmpdir:
            store = RunStore(tmpdir)
            _record_completed_run(store, "kafka-cluster", 5, status="failed")
            target = _make_target("kafka-cluster")
            self.assertEqual(find_existing_seeds(store, target, [5]), {5})


# --- sweep_events resume behaviour ------------------------------------------


def _stub_run_once_factory(report: list[dict]):
    """Return a function that mimics run_once: records every call and returns a
    canned passed=True result for each seed."""

    calls: list[int] = []

    def _stub(project_root, target, seed, name, runs_dir=None, **kwargs):
        calls.append(seed)
        report.append({"seed": seed, "name": name})
        run_dir = os.path.join(runs_dir or "/tmp", f"stub-{seed}")
        return True, [{"name": f"stub-property-seed-{seed}", "status": "passed"}], run_dir, _StubResult(returncode=0)

    return _stub, calls


class SweepEventsResumeTests(unittest.TestCase):
    def test_default_does_not_skip_any_seed(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            store = RunStore(tmpdir)
            _record_completed_run(store, "kafka-cluster", 3)
            target = _make_target("kafka-cluster")
            stub, calls = _stub_run_once_factory([])
            with patch("topotestix.orchestrator.run_once", side_effect=stub):
                events = list(sweep_events(os.getcwd(), target, [1, 2, 3, 4], runs_dir=tmpdir))
            # All four seeds were run; no skip events.
            self.assertEqual(sorted(calls), [1, 2, 3, 4])
            self.assertEqual([e.type for e in events if e.type == "run_skipped"], [])

    def test_resume_skips_seeds_with_existing_run(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            store = RunStore(tmpdir)
            _record_completed_run(store, "kafka-cluster", 2)
            _record_completed_run(store, "kafka-cluster", 4)
            target = _make_target("kafka-cluster")
            stub, calls = _stub_run_once_factory([])
            with patch("topotestix.orchestrator.run_once", side_effect=stub):
                events = list(sweep_events(os.getcwd(), target, [1, 2, 3, 4, 5], runs_dir=tmpdir, resume=True))
            # Only seeds 1, 3, 5 actually executed.
            self.assertEqual(sorted(calls), [1, 3, 5])
            skipped_events = [e for e in events if e.type == "run_skipped"]
            self.assertEqual([e.data["seed"] for e in skipped_events], [2, 4])
            finished = [e for e in events if e.type == "sweep_finished"][0]
            self.assertEqual(finished.data["skipped"], 2)

    def test_resume_off_does_not_consult_run_store(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            store = RunStore(tmpdir)
            _record_completed_run(store, "kafka-cluster", 3)
            target = _make_target("kafka-cluster")
            stub, calls = _stub_run_once_factory([])
            with patch("topotestix.orchestrator.run_once", side_effect=stub):
                list(sweep_events(os.getcwd(), target, [3], runs_dir=tmpdir, resume=False))
            self.assertEqual(calls, [3])


# --- cmd_sweep --json output mode -------------------------------------------


class CmdSweepJsonTests(unittest.TestCase):
    def test_json_output_is_valid_json_with_expected_shape(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            target = _make_target("kafka-cluster")
            args = _make_args("1..3", json_mode=True, output_dir=tmpdir)
            stub, _ = _stub_run_once_factory([])
            with patch("topotestix.orchestrator.get_cli_target", return_value=target), \
                 patch("topotestix.orchestrator.run_once", side_effect=stub):
                buf = io.StringIO()
                with redirect_stdout(buf):
                    rc = cmd_sweep(args, os.getcwd())
            self.assertEqual(rc, 0)
            payload = json.loads(buf.getvalue())
            self.assertEqual(
                sorted(payload.keys()),
                ["completed", "failed", "failures", "skipped", "target", "total"],
            )
            self.assertEqual(payload["target"], "kafka-cluster")
            self.assertEqual(payload["total"], 3)
            self.assertEqual(payload["completed"], 3)
            self.assertEqual(payload["skipped"], 0)
            self.assertEqual(payload["failed"], 0)
            self.assertEqual(payload["failures"], [])

    def test_json_output_records_failures(self):
        def _mixed_stub(project_root, target, seed, name, runs_dir=None, **kwargs):
            run_dir = os.path.join(runs_dir or "/tmp", f"stub-{seed}")
            if seed == 2:
                return False, [{"name": f"p-{seed}", "status": "failed", "message": "boom"}], run_dir, _StubResult(returncode=1)
            return True, [{"name": f"p-{seed}", "status": "passed"}], run_dir, _StubResult(returncode=0)

        with tempfile.TemporaryDirectory() as tmpdir:
            target = _make_target("kafka-cluster")
            args = _make_args("1..3", json_mode=True, output_dir=tmpdir)
            with patch("topotestix.orchestrator.get_cli_target", return_value=target), \
                 patch("topotestix.orchestrator.run_once", side_effect=_mixed_stub):
                buf = io.StringIO()
                with redirect_stdout(buf):
                    rc = cmd_sweep(args, os.getcwd())
            self.assertEqual(rc, 1)
            payload = json.loads(buf.getvalue())
            self.assertEqual(payload["failed"], 1)
            self.assertEqual(payload["completed"], 3)
            self.assertEqual(len(payload["failures"]), 1)
            self.assertEqual(payload["failures"][0]["seed"], 2)
            self.assertEqual(payload["failures"][0]["returncode"], 1)
            self.assertTrue(payload["failures"][0]["runDir"].endswith("stub-2"))

    def test_json_output_reflects_resume_skips(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            store = RunStore(tmpdir)
            _record_completed_run(store, "kafka-cluster", 1)
            _record_completed_run(store, "kafka-cluster", 3)
            target = _make_target("kafka-cluster")
            args = _make_args("1..4", json_mode=True, output_dir=tmpdir, resume=True)
            stub, _ = _stub_run_once_factory([])
            with patch("topotestix.orchestrator.get_cli_target", return_value=target), \
                 patch("topotestix.orchestrator.run_once", side_effect=stub):
                buf = io.StringIO()
                with redirect_stdout(buf):
                    rc = cmd_sweep(args, os.getcwd())
            self.assertEqual(rc, 0)
            payload = json.loads(buf.getvalue())
            self.assertEqual(payload["total"], 4)
            self.assertEqual(payload["completed"], 2)
            self.assertEqual(payload["skipped"], 2)
            self.assertEqual(payload["failed"], 0)
            self.assertEqual(payload["failures"], [])

    def test_json_mode_suppresses_streaming_human_output(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            target = _make_target("kafka-cluster")
            args = _make_args("1..2", json_mode=True, output_dir=tmpdir)
            stub, _ = _stub_run_once_factory([])
            with patch("topotestix.orchestrator.get_cli_target", return_value=target), \
                 patch("topotestix.orchestrator.run_once", side_effect=stub):
                buf = io.StringIO()
                with redirect_stdout(buf):
                    cmd_sweep(args, os.getcwd())
            # stdout must be pure JSON (plus whitespace) — no "PASS"/"FAIL" lines.
            stdout = buf.getvalue()
            self.assertNotIn("PASS", stdout)
            self.assertNotIn("FAIL", stdout)
            self.assertNotIn("Running", stdout)
            # And it must still parse as a single JSON object.
            json.loads(stdout)


# --- CLI parser --------------------------------------------------------------


class CliParserTests(unittest.TestCase):
    def test_sweep_parser_accepts_resume_flag(self):
        from topotestix.cli import build_parser

        parser = build_parser()
        args = parser.parse_args(["orchestrator", "sweep", "kafka-cluster", "--seeds", "1..5", "--resume"])
        self.assertTrue(args.resume)

    def test_sweep_parser_resume_defaults_to_false(self):
        from topotestix.cli import build_parser

        parser = build_parser()
        args = parser.parse_args(["orchestrator", "sweep", "kafka-cluster", "--seeds", "1..5"])
        self.assertFalse(args.resume)

    def test_sweep_parser_accepts_json_flag(self):
        from topotestix.cli import build_parser

        parser = build_parser()
        args = parser.parse_args(["orchestrator", "sweep", "kafka-cluster", "--seeds", "1..5", "--json"])
        self.assertTrue(args.json)


if __name__ == "__main__":
    unittest.main()
