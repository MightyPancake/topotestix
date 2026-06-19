import json
import os
import re
from datetime import datetime, timezone
from typing import Any


def default_runs_dir(project_root: str) -> str:
    return os.path.join(project_root, ".topotestix", "runs")


def safe_name(value: str) -> str:
    return re.sub(r"[^A-Za-z0-9_.-]+", "-", value).strip("-") or "run"


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


class RunStore:
    def __init__(self, root: str):
        self.root = root
        os.makedirs(self.root, exist_ok=True)

    def create_run(self, target: str, seed: int, name: str) -> dict[str, str]:
        timestamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
        base_id = safe_name(f"{timestamp}-{target}-seed-{seed}-{name}")
        suffix = 0
        while True:
            run_id = base_id if suffix == 0 else f"{base_id}-{suffix}"
            run_dir = os.path.join(self.root, run_id)
            try:
                # Atomic create: fails if another process/thread made it first.
                os.makedirs(run_dir, exist_ok=False)
                return {"id": run_id, "dir": run_dir}
            except FileExistsError:
                suffix += 1

    def write_json(self, run_dir: str, filename: str, value: Any) -> None:
        with open(os.path.join(run_dir, filename), "w") as f:
            json.dump(value, f, indent=2, sort_keys=True)
            f.write("\n")

    def write_text(self, run_dir: str, filename: str, value: str) -> None:
        with open(os.path.join(run_dir, filename), "w") as f:
            f.write(value)

    def list_runs(self) -> list[dict[str, Any]]:
        runs = []
        if not os.path.exists(self.root):
            return runs
        for run_id in sorted(os.listdir(self.root), reverse=True):
            run_dir = os.path.join(self.root, run_id)
            meta_path = os.path.join(run_dir, "run.json")
            if not os.path.isfile(meta_path):
                continue
            with open(meta_path) as f:
                meta = json.load(f)
            meta.setdefault("id", run_id)
            meta.setdefault("runDir", run_dir)
            runs.append(meta)
        return runs

    def resolve_run(self, run_id_or_path: str) -> str:
        if os.path.isdir(run_id_or_path):
            return run_id_or_path
        candidate = os.path.join(self.root, run_id_or_path)
        if os.path.isdir(candidate):
            return candidate
        matches = [run for run in self.list_runs() if run["id"].startswith(run_id_or_path)]
        if len(matches) == 1:
            return matches[0]["runDir"]
        if not matches:
            raise FileNotFoundError(f"unknown run: {run_id_or_path}")
        raise ValueError(f"ambiguous run prefix: {run_id_or_path}")
