"""Protect complete resource observations and reject misleading summaries."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("idle", ROOT / "scripts/summarize_idle_resources.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class IdleResourceTests(unittest.TestCase):
    def rows(self, scenario="empty"):
        records = [dict(module.HEADER, scenario=scenario, machTimebaseNumerator=1, machTimebaseDenominator=1)]
        for index in range(61):
            # Each read takes 100 ns; the next starts one second after it ends.
            start = index * 1_000_000_100
            records.append({"record": "sample", "index": index,
                            "elapsedBeforeReadNanoseconds": start,
                            "elapsedAfterReadNanoseconds": start + 100,
                            "userTimeMachTicks": 900_000_000 + index * 2_000_000,
                            "systemTimeMachTicks": 100_000_000 + index * 1_000_000,
                            "residentBytes": 64 * 1024**2, "physicalFootprintBytes": 32 * 1024**2,
                            "applicationActive": True})
        records.append(dict(module.FINISH))
        return records

    def raw(self, records=None, scenario="empty"):
        return b"".join(json.dumps(row).encode() + b"\n" for row in
                        (self.rows(scenario) if records is None else records))

    def testCPUUsesCounterDeltaAndElapsedTimeWithoutDividingByCoreCount(self):
        result = module.summarize([self.raw(), self.raw(scenario="fiveMiB")])
        empty = result["results"][0]
        self.assertEqual(empty["sampleCount"], 61)
        self.assertEqual(empty["cpuTimeNanoseconds"], 180_000_000)
        self.assertAlmostEqual(empty["averageCPUPercentOfOneCore"], 0.3, places=6)
        self.assertLess(empty["cpuPercentLowerBound"], empty["averageCPUPercentOfOneCore"])
        self.assertGreater(empty["cpuPercentUpperBound"], empty["averageCPUPercentOfOneCore"])
        self.assertEqual(empty["resident"]["finalBytes"], 64 * 1024**2)
        self.assertEqual(empty["physicalFootprint"]["finalBytes"], 32 * 1024**2)
        self.assertFalse(result["energyMeasured"])
        self.assertEqual(result["independentRunsPerScenario"], 1)
        self.assertNotIn("passed", result)

    def testOutlierAndEveryRawSampleRemainInSummary(self):
        rows = self.rows()
        rows[30]["residentBytes"] = 512 * 1024**2
        for row in rows[30:-1]:
            row["userTimeMachTicks"] += 2_000_000_000
        result = module.decode(self.raw(rows))
        self.assertEqual(result["resident"]["maximumBytes"], 512 * 1024**2)
        self.assertEqual(result["resident"]["medianBytes"], 64 * 1024**2)
        self.assertEqual(result["resident"]["p95Bytes"], 64 * 1024**2)
        self.assertEqual(result["observations"], rows[1:-1])
        self.assertGreater(max(result["intervalCPUPercentOfOneCore"]), 100)
        self.assertGreater(result["averageCPUPercentOfOneCore"], 3)

    def testNonUnityMachTimebaseIsAppliedOnceToCounterDeltas(self):
        rows = self.rows()
        rows[0].update(machTimebaseNumerator=125, machTimebaseDenominator=3)
        result = module.decode(self.raw(rows))
        self.assertEqual(result["cpuTimeMachTicks"], 180_000_000)
        self.assertEqual(result["cpuTimeNanoseconds"], 7_500_000_000)
        self.assertAlmostEqual(result["averageCPUPercentOfOneCore"], 12.5, places=5)
        self.assertEqual(result["observations"], rows[1:-1])
        for field in ["machTimebaseNumerator", "machTimebaseDenominator"]:
            for value in [0, -1, True, 1.5, 2**32, None]:
                bad = self.rows()
                bad[0][field] = value
                with self.subTest(field=field, value=value), self.assertRaises(ValueError):
                    module.decode(self.raw(bad))

    def testMissingDuplicateReorderedCasesAreRejected(self):
        for recordings in [[], [self.raw()], [self.raw(), self.raw()],
                           [self.raw(scenario="fiveMiB"), self.raw()],
                           [self.raw(), self.raw(scenario="fiveMiB"), self.raw()]]:
            with self.subTest(count=len(recordings)), self.assertRaises(ValueError):
                module.summarize(recordings)

    def testProtocolUnitsAndVerifiedFinishMustBeExact(self):
        mismatched = self.rows("fiveMiB")
        mismatched[0]["machTimebaseNumerator"] = 2
        with self.assertRaises(ValueError):
            module.summarize([self.raw(), self.raw(mismatched)])
        for position, field, value in [(0, "schema", True), (0, "cpuUnit", "microseconds"),
                                       (0, "memoryUnit", "KiB"), (0, "settlingSeconds", 1),
                                       (0, "plannedIntervals", 59), (-1, "normalTermination", 1),
                                       (-1, "exactFixtureVerification", False)]:
            rows = self.rows()
            rows[position][field] = value
            with self.subTest(field=field), self.assertRaises(ValueError):
                module.decode(self.raw(rows))

    def testPartialMalformedAndPayloadFieldsAreRejected(self):
        bad = [b"", self.raw()[:-1], b"not JSON\n", self.raw(self.rows()[:-1]),
               self.raw(self.rows()[:20] + self.rows()[21:])]
        for field, value in [("noteText", "unexpected"), ("index", True), ("residentBytes", -1),
                             ("physicalFootprintBytes", 0), ("residentBytes", 2**64),
                             ("systemTimeMachTicks", 0.5), ("applicationActive", False)]:
            rows = self.rows()
            rows[3][field] = value
            bad.append(self.raw(rows))
        for raw in bad:
            with self.assertRaises(ValueError):
                module.decode(raw)
        duplicate = self.raw().replace(b'"schema": 1', b'"schema": 1, "schema": 1', 1)
        with self.assertRaises(ValueError):
            module.decode(duplicate)

    def testCounterResetInvalidReadBoundsAndShortenedIntervalsAreRejected(self):
        for field, value in [("userTimeMachTicks", 0), ("systemTimeMachTicks", 0),
                             ("elapsedBeforeReadNanoseconds", 0),
                             ("elapsedAfterReadNanoseconds", 0),
                             ("elapsedAfterReadNanoseconds", 600_000_000_000)]:
            rows = self.rows()
            rows[3][field] = value
            with self.subTest(field=field), self.assertRaises(ValueError):
                module.decode(self.raw(rows))
        rows = self.rows()
        for row in rows[1:-1]:
            row["elapsedBeforeReadNanoseconds"] //= 2
            row["elapsedAfterReadNanoseconds"] //= 2
        with self.assertRaises(ValueError):
            module.decode(self.raw(rows))

    def testOnlyBoundedRegularNonSymlinkRecordingsAreRead(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            regular = root / "recording.jsonl"
            regular.write_bytes(self.raw())
            self.assertEqual(module.read_recording(regular), self.raw())
            link = root / "link"
            link.symlink_to(regular)
            for path in [link, root, root / "missing"]:
                with self.assertRaises((OSError, ValueError)):
                    module.read_recording(path)
            regular.write_bytes(b"a" * (module.MAX_BYTES + 1))
            with self.assertRaises(ValueError):
                module.read_recording(regular)

    def testOperatorAndCleanSourceGuardsStopBeforeAnyBuildOrAppLaunch(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            # Even a guard regression cannot start a nested native build in this test.
            for name, body in [("git", "printf ' M generated-dirty-source\\n'\n"),
                               ("bash", "echo 'UNEXPECTED_NESTED_BUILD' >&2\nexit 97\n")]:
                path = root / name
                path.write_text("#!/bin/sh\n" + body)
                path.chmod(0o700)
            environment = dict(os.environ, PATH=f"{root}:/usr/bin:/bin")
            for opted_in, expected in [(False, "Establish exclusive"), (True, "Commit the source")]:
                environment.pop("NOTEHUSH_EXCLUSIVE_INPUT", None)
                if opted_in:
                    environment["NOTEHUSH_EXCLUSIVE_INPUT"] = "1"
                result = subprocess.run(["/bin/bash", str(ROOT / "scripts/measure_idle_resources.sh")],
                                        env=environment, capture_output=True, text=True, timeout=5)
                self.assertEqual(result.returncode, 1)
                self.assertIn(expected, result.stderr)
                self.assertNotIn("UNEXPECTED_NESTED_BUILD", result.stderr)


if __name__ == "__main__":
    unittest.main()
