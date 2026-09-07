"""Reject a configuration that could profile a normal workspace or report debug timings."""
import copy
import importlib.util
from pathlib import Path
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("performance_build", ROOT / "scripts/verify_performance_build.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class PerformanceBuildTests(unittest.TestCase):
    def setUp(self):
        self.settings = [{"target": "NoteHush", "buildSettings": {
            "CONFIGURATION": "ReleasePerformance",
            "PRODUCT_BUNDLE_IDENTIFIER": "pk.codehub.NoteHush.PerformanceTesting",
            "EXECUTABLE_NAME": "NoteHushPerformance",
            "PRODUCT_NAME": "NoteHushPerformance", "FULL_PRODUCT_NAME": "NoteHushPerformance.app",
            "SWIFT_OPTIMIZATION_LEVEL": "-O", "SWIFT_COMPILATION_MODE": "wholemodule",
            "NOTEHUSH_TEST_WORKSPACE_REQUIRED": "YES", "NOTEHUSH_PERFORMANCE_BUILD": "YES",
            "ENABLE_HARDENED_RUNTIME": "YES",
            "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "NOTEHUSH_REQUIRE_TEST_WORKSPACE NOTEHUSH_PERFORMANCE_TESTING",
        }}]
        self.scheme = ET.Element("Scheme")
        for action in ["TestAction", "LaunchAction", "ProfileAction", "ArchiveAction", "AnalyzeAction"]:
            ET.SubElement(self.scheme, action, buildConfiguration="ReleasePerformance", selectedDebuggerIdentifier="")

    def testOptimizedIsolatedBuildIsAccepted(self):
        module.validate(self.settings, self.scheme)

    def testShippingOrUnoptimizedConfigurationIsRejected(self):
        for key, value in [
            ("CONFIGURATION", "Release"), ("PRODUCT_BUNDLE_IDENTIFIER", "pk.codehub.NoteHush"),
            ("EXECUTABLE_NAME", "NoteHush"), ("PRODUCT_NAME", "NoteHush"),
            ("FULL_PRODUCT_NAME", "NoteHush.app"),
            ("SWIFT_OPTIMIZATION_LEVEL", "-Onone"), ("NOTEHUSH_TEST_WORKSPACE_REQUIRED", "NO"),
            ("NOTEHUSH_PERFORMANCE_BUILD", "NO"), ("ENABLE_HARDENED_RUNTIME", "NO"),
            ("SWIFT_ACTIVE_COMPILATION_CONDITIONS", "DEBUG NOTEHUSH_REQUIRE_TEST_WORKSPACE NOTEHUSH_PERFORMANCE_TESTING"),
            ("SWIFT_ACTIVE_COMPILATION_CONDITIONS", "NOTEHUSH_PERFORMANCE_TESTING"),
        ]:
            with self.subTest(setting=key, value=value):
                settings = copy.deepcopy(self.settings)
                settings[0]["buildSettings"][key] = value
                with self.assertRaises(ValueError):
                    module.validate(settings, self.scheme)

    def testMissingOrAmbiguousAppSettingsAreRejected(self):
        for settings in [[], self.settings + self.settings]:
            with self.assertRaises(ValueError):
                module.validate(settings, self.scheme)

    def testEverySchemeActionMustRemainIsolated(self):
        for action in ["TestAction", "LaunchAction", "ProfileAction", "ArchiveAction", "AnalyzeAction"]:
            scheme = copy.deepcopy(self.scheme)
            scheme.find(action).set("buildConfiguration", "Release")
            with self.subTest(action=action), self.assertRaises(ValueError):
                module.validate(self.settings, scheme)

    def testAttachedDebuggerIsRejectedForRunAndTest(self):
        for action in ["TestAction", "LaunchAction"]:
            scheme = copy.deepcopy(self.scheme)
            scheme.find(action).set("selectedDebuggerIdentifier", "Xcode.DebuggerFoundation.Debugger.LLDB")
            with self.subTest(action=action), self.assertRaises(ValueError):
                module.validate(self.settings, scheme)


if __name__ == "__main__":
    unittest.main()
