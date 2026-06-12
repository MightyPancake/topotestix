import os
import tempfile
import unittest

from topotestix.run_store import RunStore


class RunStoreTests(unittest.TestCase):
    def test_create_run_and_list_metadata(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            store = RunStore(tmpdir)
            run = store.create_run("kafka-cluster", 4, "smoke")
            store.write_json(
                run["dir"],
                "run.json",
                {"id": run["id"], "target": "kafka-cluster", "seed": 4, "status": "failed"},
            )

            runs = store.list_runs()

            self.assertEqual(len(runs), 1)
            self.assertEqual(runs[0]["id"], run["id"])
            self.assertEqual(runs[0]["status"], "failed")

    def test_resolve_run_accepts_unique_prefix(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            store = RunStore(tmpdir)
            run = store.create_run("nginx", 1, "smoke")
            store.write_json(run["dir"], "run.json", {"id": run["id"]})

            self.assertEqual(store.resolve_run(run["id"][:12]), run["dir"])
            self.assertTrue(os.path.isdir(store.resolve_run(run["dir"])))


if __name__ == "__main__":
    unittest.main()
