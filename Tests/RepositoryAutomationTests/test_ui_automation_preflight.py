"""Protect unattended UI startup without modifying macOS authorization policy."""
from contextlib import redirect_stdout
import importlib.util
import io
import os
from pathlib import Path
import subprocess
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("ui_automation", ROOT / "scripts/check_ui_automation.py")
AUTOMATION = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(AUTOMATION)


def status(enabled, authentication):
    return (f"Automation Mode is {'enabled' if enabled else 'disabled'}.\n"
            f"This device {'requires' if authentication else 'DOES NOT REQUIRE'} "
            "user authentication to enable Automation Mode.\n")


class UIAutomationPreflightTests(unittest.TestCase):
    def test_all_status_combinations(self):
        for enabled in [True, False]:
            for authentication in [True, False]:
                with self.subTest(enabled=enabled, authentication=authentication):
                    self.assertEqual(AUTOMATION.parse_status(status(enabled, authentication)),
                                     (enabled, authentication))
                    result = SimpleNamespace(stdout=status(enabled, authentication), stderr="")
                    with patch.object(AUTOMATION.subprocess, "run", return_value=result), redirect_stdout(io.StringIO()):
                        self.assertEqual(AUTOMATION.run_preflight(), int(not enabled and authentication))

    def test_unknown_partial_or_appended_status_cannot_pass(self):
        for output in ["", "enabled", "Automation Mode is enabled.\n", status(False, False) * 2,
                       status(True, False) + "private-unexpected-value", status(True, False).replace("enabled", "unknown")]:
            with self.subTest(output=output):
                with self.assertRaises(ValueError):
                    AUTOMATION.parse_status(output)

    def test_status_command_is_read_only_bounded_and_uses_c_locale(self):
        result = SimpleNamespace(stdout=status(False, False), stderr="")
        with patch.object(AUTOMATION.subprocess, "run", return_value=result) as command, redirect_stdout(io.StringIO()):
            self.assertEqual(AUTOMATION.run_preflight(), 0)
        command.assert_called_once()
        self.assertEqual(command.call_args.args, (["/usr/bin/automationmodetool"],))
        self.assertEqual(command.call_args.kwargs["timeout"], 5)
        self.assertTrue(command.call_args.kwargs["check"])
        self.assertEqual(command.call_args.kwargs["env"]["LC_ALL"], "C")

    def test_command_failures_do_not_expose_output_or_exception_values(self):
        failures = [OSError("private-path"), subprocess.TimeoutExpired("private-command", 5),
                    subprocess.CalledProcessError(1, "private-command", "private-output")]
        for failure in failures:
            captured = io.StringIO()
            with patch.object(AUTOMATION.subprocess, "run", side_effect=failure), redirect_stdout(captured):
                self.assertEqual(AUTOMATION.run_preflight(), 1)
            self.assertNotIn("private-", captured.getvalue())

    def test_successful_command_with_unexpected_output_still_fails_privately(self):
        for stdout, stderr in [(status(False, False), "private-error"), ("private-output", "")]:
            captured = io.StringIO()
            with patch.object(AUTOMATION.subprocess, "run", return_value=SimpleNamespace(stdout=stdout, stderr=stderr)), redirect_stdout(captured):
                self.assertEqual(AUTOMATION.run_preflight(), 1)
            self.assertNotIn("private-", captured.getvalue())

    def test_failed_status_stops_real_shell_drivers_before_native_work_or_fixtures(self):
        for name in ["test_app.sh", "test_performance.sh", "test_interactions.sh"]:
            with self.subTest(script=name), tempfile.TemporaryDirectory() as folder:
                root = Path(folder)
                scripts = root / "scripts"
                scripts.mkdir()
                (scripts / name).write_text((ROOT / "scripts" / name).read_text())
                (scripts / "check_runner_storage.py").write_text("raise SystemExit(0)\n")
                (scripts / "check_ui_automation.py").write_text("raise SystemExit(1)\n")
                (scripts / "volume_fixture.py").write_text(
                    "import os\nfrom pathlib import Path\n"
                    "Path(os.environ['NOTEHUSH_TEST_NATIVE_MARKER']).touch()\nraise SystemExit(97)\n")
                (scripts / "build_performance.sh").write_text(
                    '#!/bin/bash\ntouch "$NOTEHUSH_TEST_NATIVE_MARKER"\nexit 97\n')
                commands = root / "bin"
                commands.mkdir()
                marker = root / "native-work-started"
                for command in ["xcodebuild", "swift", "codesign", "hdiutil"]:
                    path = commands / command
                    path.write_text('#!/bin/bash\ntouch "$NOTEHUSH_TEST_NATIVE_MARKER"\nexit 97\n')
                    path.chmod(0o700)
                result = subprocess.run(
                    ["/bin/bash", str(scripts / name)], capture_output=True, text=True, timeout=5,
                    env=dict(os.environ, PATH=str(commands) + os.pathsep + os.environ["PATH"],
                             NOTEHUSH_TEST_NATIVE_MARKER=str(marker)))
                self.assertEqual(result.returncode, 1, result.stderr)
                self.assertFalse(marker.exists())
                self.assertFalse((root / "build").exists())


if __name__ == "__main__":
    unittest.main()
