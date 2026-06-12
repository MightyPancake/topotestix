import json
import os
import tempfile
import unittest

from topotestix.reports import read_report_path, report_passed, report_summary


class ReportTests(unittest.TestCase):
    def test_report_helpers(self):
        report = [
            {"name": "a", "status": "passed"},
            {"name": "b", "status": "failed", "message": "boom"},
        ]

        self.assertFalse(report_passed(report))
        self.assertEqual(report_summary(report), {"passed": 1, "failed": 1, "total": 2})

    def test_read_report_from_run_directory(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            report_path = os.path.join(tmpdir, "report.json")
            with open(report_path, "w") as f:
                json.dump([{"name": "p", "status": "passed"}], f)

            self.assertEqual(read_report_path(tmpdir), [{"name": "p", "status": "passed"}])


if __name__ == "__main__":
    unittest.main()
