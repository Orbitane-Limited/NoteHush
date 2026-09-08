"""Exercise capacity boundaries, private errors and fail-fast shell entry points."""
from contextlib import redirect_stdout
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("runner_storage", ROOT / "scripts/check_runner_storage.py")
STORAGE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(STORAGE)


class RunnerStorageTests(unittest.TestCase):
    def test_fixed_and_proportional_boundaries_require_actual_free_bytes(self):
        for total, required in [(100 * STORAGE.GIB, 20 * STORAGE.GIB),
                                (1000 * STORAGE.GIB + 1, 100 * STORAGE.GIB + 1)]:
            for difference, status in [(-1, "insufficient"), (0, "pass"), (1, "pass")]:
                with self.subTest(total=total, difference=difference):
                    result = STORAGE.assess_capacity("workspace", total, required + difference)
                    self.assertEqual(result["requiredBytes"], required)
                    self.assertEqual(result["status"], status)

    def test_invalid_capacity_cannot_pass(self):
        for total, free in [(0, 0), (-1, 0), (10, -1), (10, 11),
                            (True, 0), (100, False), (100.0, 10), (100, None)]:
            with self.subTest(total=total, free=free):
                self.assertEqual(STORAGE.assess_capacity("workspace", total, free),
                                 {"volume": "workspace", "status": "unavailable"})

    def test_either_volume_can_block_and_each_report_is_retained(self):
        enough = SimpleNamespace(total=100 * STORAGE.GIB, free=30 * STORAGE.GIB)
        low = SimpleNamespace(total=100 * STORAGE.GIB, free=10 * STORAGE.GIB)
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            with redirect_stdout(io.StringIO()):
                for samples in [(enough, low), (low, enough), (enough, enough)]:
                    with patch.object(STORAGE.shutil, "disk_usage", side_effect=samples):
                        self.assertEqual(STORAGE.run_preflight(root, root),
                                         0 if samples == (enough, enough) else 1)
            reports = [json.loads(p.read_text()) for p in (root / "build/logs").glob("*.json")]
            self.assertEqual(len(reports), 3)
            self.assertEqual(sorted(r["status"] for r in reports), ["fail", "fail", "pass"])
            self.assertTrue(all(r["recordedAt"] for r in reports))
            self.assertTrue(all(folder not in json.dumps(r) for r in reports))

    def test_unreadable_capacity_fails_without_disclosing_exception_path(self):
        with tempfile.TemporaryDirectory() as folder:
            captured = io.StringIO()
            with patch.object(STORAGE.shutil, "disk_usage", side_effect=OSError("private-note-path")):
                with redirect_stdout(captured):
                    self.assertEqual(STORAGE.run_preflight(Path(folder), Path(folder)), 1)
            self.assertNotIn("private-note-path", captured.getvalue())
            report = json.loads(next((Path(folder) / "build/logs").glob("*.json")).read_text())
            self.assertEqual([v["status"] for v in report["volumes"]], ["unavailable"] * 2)

    def test_report_write_failure_cannot_claim_success(self):
        enough = SimpleNamespace(total=100 * STORAGE.GIB, free=30 * STORAGE.GIB)
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / "build").write_text("occupied")
            with patch.object(STORAGE.shutil, "disk_usage", return_value=enough):
                with redirect_stdout(io.StringIO()):
                    self.assertEqual(STORAGE.run_preflight(root, root), 1)

    def test_failed_gate_stops_every_native_entry_point_before_work(self):
        entry_points = ["check.sh", "test_app.sh", "archive.sh", "build_performance.sh",
                        "test_performance.sh", "profile_performance.sh", "test_interactions.sh"]
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            scripts = root / "scripts"
            scripts.mkdir()
            (scripts / "check_runner_storage.py").write_text("raise SystemExit(1)\n")
            commands = root / "bin"
            commands.mkdir()
            marker = root / "native-work-started"
            for name in ["xcodebuild", "swift", "codesign", "hdiutil", "lipo"]:
                command = commands / name
                command.write_text('#!/bin/bash\ntouch "$NOTEHUSH_TEST_NATIVE_MARKER"\nexit 97\n')
                command.chmod(0o700)
            environment = dict(os.environ, PATH=str(commands) + os.pathsep + os.environ["PATH"],
                               NOTEHUSH_TEST_NATIVE_MARKER=str(marker))
            for name in entry_points:
                with self.subTest(script=name):
                    target = scripts / name
                    target.write_text((ROOT / "scripts" / name).read_text())
                    result = subprocess.run(["/bin/bash", str(target)], env=environment,
                                            capture_output=True, text=True, timeout=5)
                    self.assertEqual(result.returncode, 1, result.stderr)
                    self.assertFalse(marker.exists())
                    self.assertFalse((root / "build").exists())

    def test_space_loss_after_build_stops_measurement_fixture_creation(self):
        for name in ["test_performance.sh", "profile_performance.sh", "test_interactions.sh"]:
            with self.subTest(script=name), tempfile.TemporaryDirectory() as folder:
                root = Path(folder)
                scripts = root / "scripts"
                scripts.mkdir()
                (scripts / name).write_text((ROOT / "scripts" / name).read_text())
                (scripts / "build_performance.sh").write_text("#!/bin/bash\nexit 0\n")
                # The first check passes; building consumes the available margin.
                (scripts / "check_runner_storage.py").write_text(
                    "from pathlib import Path\n"
                    "p = Path('capacity-check-count')\n"
                    "count = int(p.read_text()) + 1 if p.exists() else 1\n"
                    "p.write_text(str(count))\n"
                    "raise SystemExit(0 if count == 1 else 1)\n")
                commands = root / "bin"
                commands.mkdir()
                marker = root / "fixture-created"
                swift = commands / "swift"
                swift.write_text(
                    '#!/bin/bash\n'
                    'if [[ "$*" == "build --show-bin-path" ]]; then\n'
                    '  printf "%s\\n" "$NOTEHUSH_TEST_BINARY_DIRECTORY"\n'
                    'elif [[ "$*" != "build --product PerformanceFixtureHarness" ]]; then\n'
                    '  exit 98\n'
                    'fi\n')
                swift.chmod(0o700)
                harness = commands / "PerformanceFixtureHarness"
                harness.write_text(
                    '#!/bin/bash\ntouch "$NOTEHUSH_TEST_FIXTURE_MARKER"\nexit 97\n')
                harness.chmod(0o700)
                environment = dict(
                    os.environ, PATH=str(commands) + os.pathsep + os.environ["PATH"],
                    NOTEHUSH_TEST_BINARY_DIRECTORY=str(commands),
                    NOTEHUSH_TEST_FIXTURE_MARKER=str(marker))
                result = subprocess.run(["/bin/bash", str(scripts / name)], env=environment,
                                        capture_output=True, text=True, timeout=5)
                self.assertEqual(result.returncode, 1, result.stderr)
                self.assertEqual((root / "capacity-check-count").read_text(), "2")
                self.assertFalse(marker.exists())


if __name__ == "__main__":
    unittest.main()
