import json
import threading

from .orchestrator import get_cli_target, inspect_seed, parse_seed_range, run_once_events


def cmd_tui(args, project_root: str) -> int:
    try:
        from textual.app import App, ComposeResult
        from textual.containers import Horizontal, Vertical
        from textual.widgets import DataTable, Footer, Header, Static
    except ImportError as exc:
        raise RuntimeError("Textual is required for the TUI; enter the Nix dev shell or install textual") from exc

    class TopoTestixApp(App):
        CSS = """
        #summary { height: 7; border: solid $accent; padding: 1; }
        #details { height: 1fr; border: solid $accent; padding: 1; }
        DataTable { height: 1fr; }
        """
        BINDINGS = [
            ("q", "quit", "Quit"),
            ("r", "run_next", "Run next seed"),
            ("enter", "show_selected", "Show selected run"),
        ]

        def __init__(self):
            super().__init__()
            self.target = get_cli_target(project_root, args)
            self.seeds = parse_seed_range(args.seeds)
            self.index = 0
            self.passed = 0
            self.failed = 0
            self.runs = []
            self.current_inspection = None
            self.current_seed = None
            self.running = False
            self.closing = False

        def compose(self) -> ComposeResult:
            yield Header()
            with Vertical():
                yield Static(self.summary_text(), id="summary")
                with Horizontal():
                    self.table = DataTable()
                    self.table.add_columns("Status", "Seed", "Run directory")
                    yield self.table
                    yield Static("Starting first seed. Press r to run next seed. Press enter to inspect selected run.", id="details")
            yield Footer()

        def on_mount(self) -> None:
            self.call_later(self.action_run_next)

        def summary_text(self) -> str:
            return (
                f"Target: {self.target.name}\n"
                f"Progress: {self.index}/{len(self.seeds)}  Passed: {self.passed}  Failed: {self.failed}\n"
                f"Current seed: {self.current_seed or '-'}  Status: {'running' if self.running else 'idle'}\n"
                f"Topology target: {self.target.topology_target}\n"
                f"Config target: {self.target.config_target}"
            )

        def update_summary(self) -> None:
            self.query_one("#summary", Static).update(self.summary_text())

        def action_run_next(self) -> None:
            if self.running or self.index >= len(self.seeds):
                return
            seed = self.seeds[self.index]
            self.index += 1
            name = args.name or f"{self.target.name}-seed-{seed}"
            self.current_seed = seed
            self.running = True
            self.query_one("#details", Static).update(f"Seed {seed} is starting. Inspecting fuzzed topology/options...")
            self.update_summary()
            thread = threading.Thread(target=self.run_seed_background, args=(seed, name), daemon=True)
            thread.start()

        def run_seed_background(self, seed: int, name: str) -> None:
            try:
                inspection = inspect_seed(project_root, self.target, seed)
                self.safe_call_from_thread(self.show_running_inspection, seed, inspection)
                passed = False
                run_dir = ""
                for item in run_once_events(project_root, self.target, seed, name, runs_dir=args.output_dir):
                    if item.type in {"run_passed", "run_failed"}:
                        passed = item.type == "run_passed"
                        run_dir = item.data["runDir"]
                self.safe_call_from_thread(self.finish_seed, seed, passed, run_dir, inspection)
            except Exception as exc:
                self.safe_call_from_thread(self.finish_seed_error, seed, exc)

        def safe_call_from_thread(self, callback, *args) -> None:
            if self.closing:
                return
            try:
                self.call_from_thread(callback, *args)
            except Exception:
                return

        def show_running_inspection(self, seed: int, inspection: dict) -> None:
            self.current_inspection = inspection
            self.query_one("#details", Static).update(self.inspection_text(seed, inspection))

        def finish_seed(self, seed: int, passed: bool, run_dir: str, inspection: dict) -> None:
            if passed:
                self.passed += 1
            else:
                self.failed += 1
            self.running = False
            self.runs.append({
                "status": "PASS" if passed else "FAIL",
                "seed": seed,
                "runDir": run_dir,
                "inspection": inspection,
            })
            self.table.add_row("PASS" if passed else "FAIL", str(seed), run_dir)
            self.update_summary()
            if self.index < len(self.seeds) and not self.closing:
                self.call_later(self.action_run_next)

        def finish_seed_error(self, seed: int, exc: Exception) -> None:
            self.failed += 1
            self.running = False
            self.runs.append({"status": "ERROR", "seed": seed, "runDir": "", "inspection": {}, "error": str(exc)})
            self.table.add_row("ERROR", str(seed), str(exc))
            self.query_one("#details", Static).update(f"Seed {seed} failed before VM completion:\n{exc}")
            self.update_summary()

        def inspection_text(self, seed: int, inspection: dict) -> str:
            topology = json.dumps(inspection.get("topology", {}), indent=2, sort_keys=True)
            topology_choices = json.dumps(inspection.get("topologyChoices", {}), indent=2, sort_keys=True)
            role_fuzz = json.dumps(inspection.get("roleFuzz", {}), indent=2, sort_keys=True)
            node_roles = json.dumps(inspection.get("nodeRoles", {}), indent=2, sort_keys=True)
            return (
                f"Seed: {seed}\n\n"
                f"Node roles:\n{node_roles}\n\n"
                f"Topology:\n{topology}\n\n"
                f"Topology choices:\n{topology_choices}\n\n"
                f"Fuzzed config by role:\n{role_fuzz}"
            )

        def action_show_selected(self) -> None:
            row = self.table.cursor_row
            if row is None or row >= len(self.runs):
                return
            run = self.runs[row]
            inspection = run.get("inspection", {})
            self.query_one("#details", Static).update(
                f"Selected run\nStatus: {run['status']}\nSeed: {run['seed']}\nRun directory: {run['runDir']}\n\n"
                + self.inspection_text(run["seed"], inspection)
            )

        def action_quit(self) -> None:
            self.closing = True
            self.exit()

    TopoTestixApp().run()
    return 0
