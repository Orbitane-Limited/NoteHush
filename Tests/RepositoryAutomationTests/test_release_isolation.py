"""A correctly labeled archive still fails when diagnostic code reaches its binary."""
import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("release_isolation", ROOT / "scripts/verify_configuration.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class ReleaseIsolationTests(unittest.TestCase):
    def setUp(self):
        self.info = {"NoteHushRequiresTestWorkspace": "NO", "NoteHushPerformanceBuild": "NO"}

    def testShippingMetadataAndBinaryAreAccepted(self):
        module.validate_release_isolation(self.info, b"NoteHush native application")

    def testEnabledOrMissingMetadataIsRejected(self):
        for key in self.info:
            for value in [None, "YES", True]:
                with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                    module.validate_release_isolation({**self.info, key: value}, b"NoteHush")

    def testEveryFixtureAndInteractionMarkerIsRejectedDespiteShippingMetadata(self):
        for marker in [b"NOTEHUSH_TEST_WORKSPACE", b"ProcessToEditorReady", b"performance-editor-ready",
                       b"PerformanceApplication", b"TypingEventDispatch", b"TabEventDispatch", b"performance-event-"]:
            with self.subTest(marker=marker), self.assertRaises(ValueError):
                module.validate_release_isolation(self.info, b"prefix" + marker + b"suffix")


if __name__ == "__main__":
    unittest.main()
