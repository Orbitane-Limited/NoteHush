"""Keep live app-only malloc-history extraction bounded and failure-retaining."""

from pathlib import Path
import importlib.util
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "export_malloc_history", ROOT / "scripts" / "export_malloc_history.py"
)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class MallocHistoryExportTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.xml = self.root / "allocations.xml"
        self.output = self.root / "malloc-history.txt"
        self.xml.write_text(
            """<?xml version="1.0"?>
            <trace-query-result><node>
              <row address="0x1000" category="Malloc 8 Bytes" live="true"
                   responsible-caller="Small.call()" size="8"
                   responsible-library="NoteHushPerformance"/>
              <row address="0x2000" category="Malloc 32 Bytes" live="true"
                   responsible-caller="Large.call()" size="32"
                   responsible-library="NoteHushPerformance"/>
              <row address="0x3000" category="Malloc 16 Bytes" live="true"
                   responsible-caller="Large.call()" size="16"
                   responsible-library="NoteHushPerformance"/>
              <row address="0x4000" category="Malloc 64 Bytes" live="false"
                   responsible-caller="Dead.call()" size="64"
                   responsible-library="NoteHushPerformance"/>
              <row address="0x5000" category="Malloc 128 Bytes" live="true"
                   responsible-caller="System.call()" size="128"
                   responsible-library="AppKit"/>
              <row address="not-an-address" category="Malloc 256 Bytes" live="true"
                   responsible-caller="Invalid.call()" size="256"
                   responsible-library="NoteHushPerformance"/>
            </node></trace-query-result>""",
            encoding="utf-8",
        )

    def testSelectsLargestLiveAppAllocationsByUniqueCaller(self):
        result = MODULE.app_allocations(self.xml, "NoteHushPerformance", 8)
        self.assertEqual(
            result,
            [
                {"address": "0x2000", "caller": "Large.call()", "size": "32"},
                {"address": "0x1000", "caller": "Small.call()", "size": "8"},
            ],
        )

    def testRunsOnlyBoundedTargetedHistoryQueriesAndRetainsStacks(self):
        commands = []

        def runner(command, **kwargs):
            commands.append((command, kwargs))
            return subprocess.CompletedProcess(command, 0, "frame: NoteHushPerformance\n", "")

        result = MODULE.collect(42, self.xml, self.output, runner=runner)
        self.assertEqual(result, 0)
        self.assertEqual(len(commands), 2)
        self.assertEqual(commands[0][0], [
            "/usr/bin/sudo", "-n", "/usr/bin/malloc_history", "42", "-fullStacks", "0x2000"
        ])
        self.assertEqual(commands[0][1]["timeout"], 10)
        output = self.output.read_text(encoding="utf-8")
        self.assertIn("responsible-caller=Large.call()", output)
        self.assertIn("frame: NoteHushPerformance", output)

    def testFailedHistoryRetainsItsOutputAndStopsFurtherQueries(self):
        commands = []

        def runner(command, **kwargs):
            commands.append(command)
            return subprocess.CompletedProcess(command, 1, "", "permission denied\n")

        result = MODULE.collect(42, self.xml, self.output, runner=runner)
        self.assertEqual(result, 1)
        self.assertEqual(len(commands), 1)
        output = self.output.read_text(encoding="utf-8")
        self.assertIn("exit_status=1", output)
        self.assertIn("permission denied", output)

    def testTimedOutHistoryRetainsPartialOutput(self):
        def runner(command, **_kwargs):
            raise subprocess.TimeoutExpired(command, 10, output=b"partial stack", stderr=b"timed out")

        result = MODULE.collect(42, self.xml, self.output, runner=runner)
        self.assertEqual(result, 1)
        output = self.output.read_text(encoding="utf-8")
        self.assertIn("reason=TimeoutExpired", output)
        self.assertIn("partial stack", output)
        self.assertIn("timed out", output)

    def testMissingAppRowsFailsWithARecord(self):
        self.xml.write_text("<trace-query-result><node/></trace-query-result>", encoding="utf-8")
        result = MODULE.collect(42, self.xml, self.output, runner=lambda *_a, **_k: None)
        self.assertEqual(result, 1)
        self.assertIn("status=noLiveAppAllocations", self.output.read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
