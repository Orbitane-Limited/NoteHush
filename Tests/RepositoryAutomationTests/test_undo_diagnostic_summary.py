"""Keep diagnostic conclusions separate from unknown text and missing observations."""
import copy
import importlib.util
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("undo_summary", ROOT / "scripts/summarize_undo_diagnostic.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class UndoDiagnosticSummaryTests(unittest.TestCase):
    def setUp(self):
        base = {key: False for key in module.FLAGS}
        base.update(sequence=0, elapsedSeconds=0.0, event="installed", fixtureState="noEditor")
        self.rows = [base]
        for index, event, state in [(1, "commandZ", "singleFirst"), (2, "willUndo", "singleFirst"),
                                    (3, "didUndo", "original")]:
            row = dict(base, sequence=index, elapsedSeconds=index / 10, event=event,
                       fixtureState=state, applicationActive=True, workspaceKey=True,
                       editorFirstResponder=True)
            if event in {"willUndo", "didUndo"}:
                row["notificationFromEditor"] = True
            self.rows.append(row)

    def encoded(self, rows=None):
        return b"".join(json.dumps(row).encode() + b"\n" for row in (rows or self.rows))

    def testAppStateAndUndoAreReportedWithoutClaimingTestOrShutdownSuccess(self):
        result = module.summarize(self.encoded())
        self.assertEqual(result["commandZCount"], 1)
        self.assertEqual(result["editorUndoCount"], 1)
        self.assertEqual(result["otherUndoCount"], 0)
        self.assertFalse(result["shutdownObserved"])
        self.assertEqual(result["observations"][-1]["fixtureState"], "original")
        rows = copy.deepcopy(self.rows)
        rows[-1]["notificationFromEditor"] = False
        self.assertEqual(module.summarize(self.encoded(rows))["otherUndoCount"], 1)

    def testUnexpectedTextFieldsAndClassificationValuesAreRejected(self):
        for field, value in [("text", "unexpected fixture input"), ("fixtureState", "unexpected"),
                             ("event", "unexpected"), ("editorCanUndo", "true"),
                             ("notificationFromEditor", None)]:
            rows = copy.deepcopy(self.rows)
            rows[-1][field] = value
            with self.subTest(field=field), self.assertRaises(ValueError):
                module.summarize(self.encoded(rows))

    def testMissingReorderedNonfiniteAndPartialRecordsAreRejected(self):
        cases = [self.encoded()[:-1], b"not JSON\n", self.encoded(self.rows[1:])]
        for field, value in [("sequence", True), ("sequence", 10), ("elapsedSeconds", float("nan")),
                             ("elapsedSeconds", -1), ("elapsedSeconds", 0.01)]:
            rows = copy.deepcopy(self.rows)
            rows[-1][field] = value
            cases.append(self.encoded(rows))
        for raw in cases:
            with self.assertRaises(ValueError):
                module.summarize(raw)

    def testRecordCapRemainsAnExplicitLimitation(self):
        rows = copy.deepcopy(self.rows)
        rows[-1]["event"] = "limitReached"
        self.assertTrue(module.summarize(self.encoded(rows))["limitReached"])


if __name__ == "__main__":
    unittest.main()
