import unittest
from unittest.mock import patch

from topotestix.cli import build_parser
from topotestix.orchestrator import (
    generate_inspect_expr,
    parse_seed_range,
    reproduce_command,
    run_once_events,
    sweep_events,
)
from topotestix.targets import Target


class CliTests(unittest.TestCase):
    def test_orchestrator_run_accepts_target_seed(self):
        args = build_parser().parse_args(["orchestrator", "run", "kafka", "--seed", "7"])

        self.assertEqual(args.command, "orchestrator")
        self.assertEqual(args.orchestrator_command, "run")
        self.assertEqual(args.target, "kafka")
        self.assertEqual(args.seed, 7)

    def test_targets_list_accepts_local_project_root(self):
        args = build_parser().parse_args(["targets", "list", "--project-root", "."])

        self.assertEqual(args.command, "targets")
        self.assertEqual(args.targets_command, "list")
        self.assertEqual(args.project_root, ".")

    def test_global_project_root_survives_subparser_defaults(self):
        args = build_parser().parse_args(["--project-root", "/repo", "targets", "list"])

        self.assertEqual(args.project_root, "/repo")

    def test_seed_range_parses_inclusive_range(self):
        self.assertEqual(parse_seed_range("2..4"), [2, 3, 4])

    def test_seed_range_parses_comma_list(self):
        self.assertEqual(parse_seed_range("1,3,5"), [1, 3, 5])

    def test_runs_list_accepts_output_dir(self):
        args = build_parser().parse_args(["runs", "list", "--output-dir", "/tmp/runs"])

        self.assertEqual(args.output_dir, "/tmp/runs")

    def test_reproduce_command_includes_target_paths(self):
        target = Target(
            name="nginx",
            description="",
            topology_target="targets/topology/single-machine.nix",
            config_target="targets/config/nginx.nix",
            base_module="targets/nginx/module.nix",
            test_script="targets/nginx/test-script.py",
            properties="targets/nginx/properties.nix",
            report_node="machine1",
        )

        command = reproduce_command("/repo", target, 4, "nginx-fail", {}, {})

        self.assertIn("--project-root /repo", command)
        self.assertIn("--topology-target targets/topology/single-machine.nix", command)
        self.assertIn("--properties targets/nginx/properties.nix", command)

    def test_generated_inspect_expression_contains_topology_and_role_fuzz(self):
        expr = generate_inspect_expr(
            3,
            "targets/topology/single-machine.nix",
            "targets/config/nginx.nix",
            "/repo",
        )

        self.assertIn("topologyChoices = fuzzedTopology.choices;", expr)
        self.assertIn("roleFuzz", expr)
        self.assertIn("expandTopology", expr)

    def test_sweep_events_reports_failures(self):
        target = Target(
            name="nginx",
            description="",
            topology_target="targets/topology/single-machine.nix",
            config_target="targets/config/nginx.nix",
            base_module="targets/nginx/module.nix",
            test_script="targets/nginx/test-script.py",
            properties="targets/nginx/properties.nix",
            report_node="machine1",
        )
        fake_result = type("Result", (), {"returncode": 1})()

        with patch("topotestix.orchestrator.run_once", return_value=(False, [], "/tmp/run", fake_result)):
            events = list(sweep_events("/repo", target, [4], fail_fast=True))

        self.assertEqual(events[0].type, "sweep_started")
        self.assertEqual(events[2].type, "run_failed")
        self.assertEqual(events[-1].data["failures"], 1)

    def test_run_once_events_accepts_positional_args_and_failed_messages(self):
        target = Target(
            name="nginx",
            description="",
            topology_target="targets/topology/single-machine.nix",
            config_target="targets/config/nginx.nix",
            base_module="targets/nginx/module.nix",
            test_script="targets/nginx/test-script.py",
            properties="targets/nginx/properties.nix",
            report_node="machine1",
        )
        fake_result = type("Result", (), {"returncode": 1})()
        report = [{"name": "prop", "status": "failed", "message": "boom"}]

        with patch("topotestix.orchestrator.run_once", return_value=(False, report, "/tmp/run", fake_result)):
            events = list(run_once_events("/repo", target, 4, "nginx"))

        self.assertEqual(events[0].type, "run_started")
        self.assertEqual(events[2].type, "property_failed")
        self.assertEqual(events[2].message, "boom")


if __name__ == "__main__":
    unittest.main()
