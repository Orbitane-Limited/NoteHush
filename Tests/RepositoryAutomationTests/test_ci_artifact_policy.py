"""Keep successful CI lean while preserving complete failure evidence."""
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]


def workflow_steps(path):
    lines = path.read_text().splitlines()
    steps = {}
    index = 0
    while index < len(lines):
        line = lines[index]
        if not line.startswith("      - name: "):
            index += 1
            continue
        name = line.partition(":")[2].strip()
        end = index + 1
        while end < len(lines) and not lines[end].startswith("      - name: "):
            end += 1
        steps[name] = "\n".join(lines[index:end])
        index = end
    return steps


class CIArtifactPolicyTests(unittest.TestCase):
    def test_ci_uses_public_hosted_macos_with_xcode_26_6(self):
        workflow = (ROOT / ".github/workflows/ci.yml").read_text()
        self.assertIn("runs-on: macos-26", workflow)
        self.assertIn(
            "DEVELOPER_DIR: /Applications/Xcode_26.6.app/Contents/Developer",
            workflow,
        )
        self.assertNotIn("runs-on: [self-hosted", workflow)

    def test_ci_uploads_complete_logs_only_after_failure_or_cancellation(self):
        steps = workflow_steps(ROOT / ".github/workflows/ci.yml")
        step = steps["Upload verification logs after failure or cancellation"]
        self.assertIn("if: failure() || cancelled()", step)
        self.assertIn("path: build/logs/", step)
        self.assertIn("retention-days: 7", step)
        self.assertNotIn("continue-on-error", step)
        fallback = steps["Preserve verification logs locally if upload fails"]
        self.assertIn("always()", fallback)
        self.assertIn("steps.upload_ci_logs.outcome != 'success'", fallback)
        self.assertIn("scripts/preserve_ci_failure_logs.py", fallback)

    def test_ci_only_uploads_unsigned_archives_from_successful_main_runs(self):
        steps = workflow_steps(ROOT / ".github/workflows/ci.yml")
        package = steps["Package unsigned engineering archive"]
        self.assertIn("github.ref == 'refs/heads/main'", package)
        self.assertIn("github.event_name != 'pull_request'", package)
        step = steps["Upload unsigned archive"]
        self.assertIn("if: success() && github.ref == 'refs/heads/main'", step)
        self.assertIn("github.event_name != 'pull_request'", step)
        self.assertIn("retention-days: 7", step)
        self.assertNotIn("continue-on-error", step)
        self.assertLess(
            list(steps).index("Upload unsigned archive"),
            list(steps).index("Upload verification logs after failure or cancellation"),
        )

    def test_delivery_keeps_failure_logs_and_limits_candidate_upload_to_main(self):
        steps = workflow_steps(ROOT / ".github/workflows/delivery.yml")
        logs = steps["Upload diagnostics after failure or cancellation"]
        self.assertIn("if: failure() || cancelled()", logs)
        self.assertIn("path: build/logs/", logs)
        self.assertIn("retention-days: 7", logs)
        self.assertNotIn("continue-on-error", logs)
        fallback = steps["Preserve delivery logs locally if upload fails"]
        self.assertIn("steps.upload_delivery_logs.outcome != 'success'", fallback)
        self.assertIn("scripts/preserve_ci_failure_logs.py", fallback)

        candidate = steps["Upload candidate"]
        self.assertIn("if: success() && github.ref == 'refs/heads/main'", candidate)
        self.assertIn("build/NoteHush-UNSIGNED.xcarchive.tar.gz", candidate)
        self.assertIn("retention-days: 7", candidate)
        self.assertNotIn("continue-on-error", candidate)
        self.assertLess(
            list(steps).index("Upload candidate"),
            list(steps).index("Upload diagnostics after failure or cancellation"),
        )

    def test_performance_workflow_retains_all_measurement_results_for_seven_days(self):
        steps = workflow_steps(ROOT / ".github/workflows/performance.yml")
        evidence = steps["Upload measurement evidence"]
        self.assertIn("if: always()", evidence)
        self.assertIn("path: build/logs/", evidence)
        self.assertIn("retention-days: 7", evidence)
        self.assertIn("if-no-files-found: error", evidence)
        self.assertNotIn("continue-on-error", evidence)
        fallback = steps["Preserve failed measurement evidence locally"]
        self.assertIn("steps.measure_performance.outcome != 'success'", fallback)
        self.assertIn("steps.upload_performance_evidence.outcome != 'success'", fallback)
        self.assertIn("--include-fixture-manifests", fallback)


if __name__ == "__main__":
    unittest.main()
