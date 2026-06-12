import argparse
import os
import unittest

from orchestrator.orchestrator import (
    generate_fuzz_expr,
    generate_nix_expr,
    nix_path,
    nix_string,
    parse_json_object,
)


class OrchestratorRenderingTests(unittest.TestCase):
    def test_nix_string_escapes_quotes(self):
        self.assertEqual(nix_string('name "with" quotes'), '"name \\"with\\" quotes"')

    def test_nix_path_uses_string_boundary(self):
        self.assertEqual(nix_path('/tmp/path with spaces/file.nix'), '(builtins.toPath "/tmp/path with spaces/file.nix")')

    def test_parse_json_object_rejects_non_object(self):
        with self.assertRaises(argparse.ArgumentTypeError):
            parse_json_object('[]', '--config-choices')

    def test_generated_expression_uses_json_choices_and_escaped_name(self):
        project_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        expr = generate_nix_expr(
            seed=1,
            topology_target_path='targets/topology/single-machine.nix',
            config_target_path='targets/config/nginx.nix',
            base_module_path='targets/nginx/module.nix',
            test_script_path='targets/nginx/test-script.py',
            properties_path='targets/nginx/properties.nix',
            name='nginx "quoted" test',
            project_root=project_root,
            topology_choices={'.roles.machine': 0},
            config_choices={'machine': {'.services.nginx.enable': 0}},
        )

        self.assertIn('name = "nginx \\"quoted\\" test";', expr)
        self.assertIn('topologyChoices = (builtins.fromJSON', expr)
        self.assertIn('configChoices = (builtins.fromJSON', expr)
        self.assertIn('builtins.toPath', expr)

    def test_generated_fuzz_expression_uses_safe_seed_and_path(self):
        project_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        expr = generate_fuzz_expr('seed "quoted"', 'targets/config/nginx.nix', project_root)

        self.assertIn('seed = "seed \\"quoted\\"";', expr)
        self.assertIn('target = import (builtins.toPath', expr)
        self.assertIn('lib/fuzzer.nix', expr)


if __name__ == '__main__':
    unittest.main()
