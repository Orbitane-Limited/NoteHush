"""Reject incomplete/retried metrics; preserve every observation and its declared unit."""
import copy
import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("performance_metrics", ROOT / "scripts/summarize_performance.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class PerformanceMetricsTests(unittest.TestCase):
    def fixture(self):
        return [{"testIdentifier": f"LaunchPerformanceTests/{name}()", "testRuns": [{"metrics": [
            {"displayName": "Duration (ApplicationLaunch)",
             "identifier": "com.apple.dt.XCTMetric_ApplicationLaunch-ApplicationLaunch.duration",
             "unitOfMeasurement": "s",
             "measurements": list(range(1, 21))},
            {"displayName": "Duration (ProcessToEditorReady)",
             "identifier": "com.apple.dt.XCTMetric_OSSignpost-ProcessToEditorReady.duration",
             "unitOfMeasurement": "s",
             "measurements": [500] + list(range(1, 20))},
        ]}]} for name in sorted(module.SCENARIOS)]

    def testKeepsOutlierAndUnitsAndComputesNearestRankP95(self):
        report = module.summarize(self.fixture())
        for scenario in report["scenarios"]:
            launch, ready = scenario["metrics"]
            self.assertEqual(launch["unit"], "s")
            self.assertEqual(launch["median"], 10.5)
            self.assertEqual(launch["p95"], 19)
            self.assertEqual(ready["unit"], "s")
            self.assertEqual(ready["samples"][0], 500)
            self.assertEqual(ready["count"], 20)
            self.assertEqual(ready["p95"], 19)

    def testRejectsMissingDuplicateCasesAndRetriedRuns(self):
        tests = self.fixture()
        retried = copy.deepcopy(tests)
        retried[0]["testRuns"] *= 2
        for invalid in [tests[:2], tests + tests[:1], retried, {}]:
            with self.subTest(invalid=type(invalid)), self.assertRaises(ValueError):
                module.summarize(invalid)

    def testRejectsFewNonfiniteNegativeOrBooleanSamples(self):
        for samples in [[1] * 19, [float("nan")] * 20, [float("inf")] * 20, [-1] * 20, [True] * 20]:
            tests = self.fixture()
            tests[0]["testRuns"][0]["metrics"][0]["measurements"] = samples
            with self.assertRaises(ValueError):
                module.summarize(tests)

    def testRequiresBothNamedIntervalsAndExplicitUnits(self):
        for removed in [0, 1]:
            tests = self.fixture()
            tests[0]["testRuns"][0]["metrics"].pop(removed)
            with self.assertRaises(ValueError):
                module.summarize(tests)
        tests = self.fixture()
        tests[0]["testRuns"][0]["metrics"][0]["unitOfMeasurement"] = ""
        with self.assertRaises(ValueError):
            module.summarize(tests)

    def testRejectsDifferentLaunchBoundaryUnknownUnitsAndAdditionalMetrics(self):
        for field, value in [
            ("identifier", "com.apple.dt.XCTMetric_ApplicationLaunch-ApplicationFirstFramePresentationResponsive.duration"),
            ("identifier", "unrecognized-launch-interval"),
            ("unitOfMeasurement", "ms"),
        ]:
            tests = self.fixture()
            tests[0]["testRuns"][0]["metrics"][0][field] = value
            with self.subTest(field=field, value=value), self.assertRaises(ValueError):
                module.summarize(tests)
        tests = self.fixture()
        tests[0]["testRuns"][0]["metrics"].append({
            "displayName": "Extra launch", "identifier": "extra-launch", "unitOfMeasurement": "s",
            "measurements": [1] * 20,
        })
        with self.assertRaises(ValueError):
            module.summarize(tests)


if __name__ == "__main__":
    unittest.main()
