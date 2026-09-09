import copy
import importlib.util
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
import uuid

SCRIPTS = Path(__file__).resolve().parents[2] / "scripts"
sys.path.insert(0, str(SCRIPTS))


def load(name):
    spec = importlib.util.spec_from_file_location(name, SCRIPTS / (name + ".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


summary = load("summarize_large_open")
runner = load("test_large_open")


def fixture():
    records = [copy.deepcopy(summary.HEADER)]
    for w, workload in enumerate(("ascii", "mixed")):
        for index in range(20):
            records.extend([
                dict(kind="attempt", workload=workload, index=index,
                     workspace=str(uuid.uuid4()).upper()),
                dict(kind="process", workload=workload, index=index, pid=1000 + w * 20 + index,
                     exactApplicationIdentity=True),
                dict(kind="observation", workload=workload, index=index,
                     requestToCheckpointNanoseconds=(index + 1) * 1_000_000,
                     launchServicesReturnNanoseconds=100_000, withinObservationBound=True),
                dict(kind="verification", workload=workload, index=index,
                     **{key: True for key in summary.ORACLES}),
            ])
    records.append(dict(kind="finish", verifiedObservations=40))
    context = dict(schema=1, status="pass", exclusiveInputAttested=True, collectorExitCode=0,
                   signatureBeforePassed=True, signatureAfterPassed=True,
                   workingTreeCleanBefore=True, workingTreeCleanAfter=True,
                   sourceBefore="a" * 40, sourceAfter="a" * 40,
                   binaryBefore="b" * 64, binaryAfter="b" * 64,
                   harnessBefore="c" * 64, harnessAfter="c" * 64)
    return records, context


class LargeOpenEvidenceTests(unittest.TestCase):
    def test_complete_run_uses_middle_pair_median_and_nearest_rank_p95(self):
        report = summary.summarize(*fixture())
        for result in report["workloads"].values():
            self.assertEqual(result["count"], 20)
            self.assertEqual(result["medianMilliseconds"], 10.5)
            self.assertEqual(result["p95Milliseconds"], 19)
            self.assertEqual(len(result["rawNanoseconds"]), 20)

    def test_slow_observations_are_preserved_without_prd_threshold_filtering(self):
        records, context = fixture()
        records[3]["requestToCheckpointNanoseconds"] = 9_999_999_999
        report = summary.summarize(records, context)
        self.assertEqual(report["workloads"]["ascii"]["rawNanoseconds"][0], 9_999_999_999)

    def test_partial_retried_reordered_or_failed_runs_are_rejected(self):
        records, context = fixture()
        for damaged in (records[:-1], records[:20], records + [records[-1]],
                        records[:4] + records[8:] + records[4:8],
                        records[:-1] + [dict(kind="failure", code="quitFailed")]):
            with self.subTest(rows=len(damaged)), self.assertRaises(ValueError):
                summary.summarize(damaged, context)

    def test_wrong_units_types_boundaries_and_false_oracles_are_rejected(self):
        for row, key, value in [(0, "unit", "seconds"), (0, "schema", True),
                                (3, "requestToCheckpointNanoseconds", float("nan")),
                                (3, "requestToCheckpointNanoseconds", True),
                                (3, "requestToCheckpointNanoseconds", 10_000_000_001),
                                (3, "launchServicesReturnNanoseconds", 2_000_000),
                                (3, "withinObservationBound", False),
                                (4, "normalQuit", False), (4, "completeRecovery", False)]:
            records, context = fixture()
            records[row][key] = value
            with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                summary.summarize(records, context)

    def test_reused_process_or_workspace_is_not_a_fresh_launch(self):
        for row, field in ((5, "workspace"), (6, "pid")):
            records, context = fixture()
            records[row][field] = records[row - 4][field]
            with self.assertRaises(ValueError):
                summary.summarize(records, context)

    def test_collector_exit_and_unchanged_source_binary_signature_are_required(self):
        for key, value in [("collectorExitCode", 1), ("collectorExitCode", False),
                           ("workingTreeCleanBefore", False), ("workingTreeCleanAfter", False),
                           ("sourceAfter", "d" * 40), ("binaryAfter", "d" * 64),
                           ("harnessAfter", "d" * 64), ("signatureAfterPassed", False),
                           ("exclusiveInputAttested", False), ("status", "fail")]:
            records, context = fixture()
            context[key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                summary.summarize(records, context)

    def test_duplicate_json_fields_and_nonfinite_literals_are_rejected(self):
        for text in ('{"normalQuit": false, "normalQuit": true}', '{"duration": NaN}',
                     '{"duration": Infinity}'):
            with self.assertRaises(ValueError):
                summary.read_json(text)


class LargeOpenOperatorTests(unittest.TestCase):
    def test_environment_does_not_forward_secrets_or_preexisting_fixture_controls(self):
        with patch.dict(os.environ, {"PATH": "/usr/bin", "SECRET": "sentinel",
                                     "NOTEHUSH_TEST_WORKSPACE": "unowned"}, clear=True):
            self.assertEqual(runner.environment(), {"PATH": "/usr/bin"})

    def test_existing_evidence_cannot_be_overwritten(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "context.json"
            path.write_bytes(b"previous failed evidence")
            with self.assertRaises(FileExistsError):
                runner.exclusive_json(path, {"status": "pass"})
            self.assertEqual(path.read_bytes(), b"previous failed evidence")

    def test_exclusive_input_and_clean_source_are_required_before_build(self):
        with patch.dict(os.environ, {}, clear=True), patch.object(runner, "execute") as execute:
            with self.assertRaises(SystemExit):
                runner.main()
            execute.assert_not_called()
        with patch.dict(os.environ, {"NOTEHUSH_EXCLUSIVE_INPUT": "1"}), \
                patch.object(runner, "git", return_value="dirty"), \
                patch.object(runner, "execute") as execute:
            with self.assertRaises(SystemExit):
                runner.main()
            execute.assert_not_called()

    def test_space_loss_during_build_stops_before_any_fixture_launch_and_keeps_logs(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            def execute(arguments, output, timeout):
                output.write_text("retained build output\n")
                return 0
            with patch.object(runner, "ROOT", root), \
                    patch.dict(os.environ, {"NOTEHUSH_EXCLUSIVE_INPUT": "1"}), \
                    patch.object(runner, "git", side_effect=["", "a" * 40]), \
                    patch.object(runner, "capacity", side_effect=[{"passed": True}, {"passed": False}]), \
                    patch.object(runner, "execute", side_effect=execute) as calls:
                self.assertEqual(runner.main(), 1)
                self.assertEqual(calls.call_count, 2)
            output = next((root / "build/logs").iterdir())
            self.assertFalse((output / "inputs").exists())
            self.assertEqual((output / "app-build.log").read_text(), "retained build output\n")
            context = json.loads((output / "context.json").read_text())
            self.assertEqual(context["status"], "fail")
            self.assertEqual(context["failure"], "storage-before-fixtures")

    def test_fixture_reserve_is_additional_to_existing_disk_policy(self):
        base = dict(status="pass", availableBytes=1000, requiredBytes=900)
        with patch.object(runner.check_runner_storage, "inspect_capacity", return_value=base):
            self.assertTrue(runner.capacity(Path("."), Path("."), 100)["passed"])
            self.assertFalse(runner.capacity(Path("."), Path("."), 101)["passed"])


if __name__ == "__main__":
    unittest.main()
