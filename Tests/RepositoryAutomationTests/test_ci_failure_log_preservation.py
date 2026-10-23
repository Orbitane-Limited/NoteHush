"""Preserve CI failure logs privately without overwriting or following links."""
import importlib.util
import json
from pathlib import Path
import stat
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "ci_failure_logs", ROOT / "scripts/preserve_ci_failure_logs.py"
)
PRESERVER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PRESERVER)


class CIFailureLogPreservationTests(unittest.TestCase):
    def test_copies_exact_logs_privately_and_records_path_free_integrity_summary(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "build/logs"
            (source / "Nested.xcresult/Data").mkdir(parents=True)
            (source / "validation.log").write_bytes(b"generated test result")
            (source / "Nested.xcresult/Data/record.bin").write_bytes(bytes(range(64)))
            destination = root / "runner/_failure-evidence"

            result = PRESERVER.preserve_failure_logs(source, destination, "12345", "2")

            self.assertEqual((result / "logs/validation.log").read_bytes(), b"generated test result")
            self.assertEqual(
                (result / "logs/Nested.xcresult/Data/record.bin").read_bytes(), bytes(range(64))
            )
            summary = json.loads((result / "evidence.json").read_text())
            self.assertEqual(summary["runID"], "12345")
            self.assertEqual(summary["runAttempt"], "2")
            self.assertEqual(summary["fileCount"], 2)
            self.assertEqual(summary["totalBytes"], len(b"generated test result") + 64)
            self.assertEqual(len(summary["contentTreeSHA256"]), 64)
            serialized = json.dumps(summary)
            self.assertNotIn(str(source), serialized)
            self.assertNotIn("validation.log", serialized)
            self.assertEqual(stat.S_IMODE(result.stat().st_mode), 0o700)
            self.assertEqual(stat.S_IMODE((result / "logs/validation.log").stat().st_mode), 0o600)
            self.assertTrue(source.exists(), "the source logs must remain untouched")

    def test_performance_manifests_are_kept_only_in_private_runner_copy(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            logs = root / "build/logs"
            logs.mkdir(parents=True)
            manifests = root / "build"
            private_path = "/Users/runner/Library/Containers/generated/fixture"
            (manifests / "performance-fixtures.json").write_text(
                json.dumps({"applicationURL": "/Users/runner/build/NoteHush.app", "root": private_path})
            )
            (manifests / "interaction-fixtures.json").write_text("{\"generated\":true}")
            destination = root / "runner/_failure-evidence"
            with patch.object(PRESERVER, "ROOT", root):
                result = PRESERVER.preserve_failure_logs(
                    logs, destination, "77", "1", include_fixture_manifests=True
                )

            self.assertEqual(
                (result / "fixture-manifests/performance-fixtures.json").read_text(),
                (manifests / "performance-fixtures.json").read_text(),
            )
            summary = json.loads((result / "evidence.json").read_text())
            self.assertNotIn(private_path, json.dumps(summary))
            self.assertNotIn("applicationURL", json.dumps(summary))

    def test_symlinks_invalid_identity_and_existing_run_fail_without_overwrite(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "build/logs"
            source.mkdir(parents=True)
            outside = root / "private.fixture"
            outside.write_text("never copy through a link")
            (source / "link").symlink_to(outside)
            destination = root / "runner/_failure-evidence"
            with self.assertRaisesRegex(ValueError, "nonRegularFile"):
                PRESERVER.preserve_failure_logs(source, destination, "78", "1")
            self.assertFalse((destination / "78-1").exists())
            self.assertEqual(outside.read_text(), "never copy through a link")

            (source / "link").unlink()
            (source / "log.txt").write_text("result")
            with self.assertRaisesRegex(ValueError, "invalidRunIdentity"):
                PRESERVER.preserve_failure_logs(source, destination, "78/../79", "1")

            result = PRESERVER.preserve_failure_logs(source, destination, "78", "1")
            sentinel = result / "preserve.txt"
            sentinel.write_text("keep")
            with self.assertRaisesRegex(FileExistsError, "runEvidenceAlreadyExists"):
                PRESERVER.preserve_failure_logs(source, destination, "78", "1")
            self.assertEqual(sentinel.read_text(), "keep")

    def test_empty_logs_do_not_create_an_evidence_directory(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "build/logs"
            source.mkdir(parents=True)
            destination = root / "runner/_failure-evidence"
            self.assertIsNone(PRESERVER.preserve_failure_logs(source, destination, "90", "1"))
            self.assertFalse((destination / "90-1").exists())


if __name__ == "__main__":
    unittest.main()
