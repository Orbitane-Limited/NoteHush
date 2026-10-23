"""Reject an accidental diagnostic logger in distribution/performance binaries."""
import importlib.util
from pathlib import Path
import unittest
import tempfile

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("configuration", ROOT / "scripts/verify_configuration.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class UndoDiagnosticExclusionTests(unittest.TestCase):
    def testOrdinaryExecutableAndExistingPerformanceMarkersAreAccepted(self):
        module.validate_undo_diagnostic_exclusion(b"header\0NoteHush\0ProcessToEditorReady\0trailer")

    def testEachDiagnosticEntryPointClassAndOutputMarkerIsRejected(self):
        for marker in [b"NOTEHUSH_UNDO_DIAGNOSTICS", b"UndoDiagnosticProbe", b"undo-diagnostic-"]:
            with self.subTest(marker=marker), self.assertRaises(ValueError):
                module.validate_undo_diagnostic_exclusion(b"header\0" + marker + b"\0trailer")

    def testProbeInDebugLibraryCannotHideBehindCleanLauncher(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            executable = root / "NoteHush"
            executable.write_bytes(b"launcher")
            library = root / "NoteHush.debug.dylib"
            library.write_bytes(b"ordinary app code")
            module.validate_undo_diagnostic_bundle(executable)
            library.write_bytes(b"code\0UndoDiagnosticProbe\0")
            with self.assertRaises(ValueError):
                module.validate_undo_diagnostic_bundle(executable)

    def testMissingOrSymlinkedCodeCannotPass(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            executable = root / "NoteHush"
            with self.assertRaises(ValueError):
                module.validate_undo_diagnostic_bundle(executable)
            executable.write_bytes(b"launcher")
            (root / "NoteHush.debug.dylib").symlink_to(executable)
            with self.assertRaises(ValueError):
                module.validate_undo_diagnostic_bundle(executable)


if __name__ == "__main__":
    unittest.main()
