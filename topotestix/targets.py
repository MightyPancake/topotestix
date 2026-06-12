import json
import os
from dataclasses import dataclass
from typing import Optional

from .nix import eval_json, nix_path, resolve_path


@dataclass(frozen=True)
class Target:
    name: str
    description: str
    topology_target: str
    config_target: str
    base_module: str
    test_script: str
    properties: str
    report_node: str

    @classmethod
    def from_json(cls, value: dict) -> "Target":
        return cls(
            name=value["name"],
            description=value.get("description", ""),
            topology_target=value["topologyTarget"],
            config_target=value["configTarget"],
            base_module=value["baseModule"],
            test_script=value["testScript"],
            properties=value["properties"],
            report_node=value.get("reportNode", ""),
        )

    def as_dict(self) -> dict[str, str]:
        return {
            "name": self.name,
            "description": self.description,
            "topologyTarget": self.topology_target,
            "configTarget": self.config_target,
            "baseModule": self.base_module,
            "testScript": self.test_script,
            "properties": self.properties,
            "reportNode": self.report_node,
        }


def registry_expr(project_root: str) -> str:
    registry_path = resolve_path("targets/default.nix", project_root)
    return f"""let
  targets = import {nix_path(registry_path)};
  renderTarget = name: target: {{
    inherit name;
    description = target.description or "";
    topologyTarget = toString target.topologyTarget;
    configTarget = toString target.configTarget;
    baseModule = toString target.baseModule;
    testScript = toString target.testScript;
    properties = toString target.properties;
    reportNode = target.reportNode or "";
  }};
in
builtins.listToAttrs (map (name: {{
  inherit name;
  value = renderTarget name targets.${{name}};
}}) (builtins.attrNames targets))"""


def load_targets(project_root: str) -> dict[str, Target]:
    raw = eval_json(registry_expr(project_root))
    return {name: Target.from_json(value) for name, value in raw.items()}


def get_target(project_root: str, name: str) -> Target:
    targets = load_targets(project_root)
    if name not in targets:
        available = ", ".join(sorted(targets))
        raise ValueError(f"unknown target {name!r}; available targets: {available}")
    return targets[name]


def print_targets(project_root: str, json_output: bool = False) -> None:
    targets = load_targets(project_root)
    if json_output:
        print(json.dumps({name: target.as_dict() for name, target in targets.items()}, indent=2, sort_keys=True))
        return
    for name in sorted(targets):
        target = targets[name]
        print(f"{name}\t{target.description}")


def print_target(project_root: str, name: str, json_output: bool = False) -> None:
    target = get_target(project_root, name)
    if json_output:
        print(json.dumps(target.as_dict(), indent=2, sort_keys=True))
        return
    for key, value in target.as_dict().items():
        print(f"{key}: {value}")


def project_root_from_args(value: Optional[str]) -> str:
    if value:
        return os.path.abspath(value)
    return os.getcwd()
