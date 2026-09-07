"""Keep the required-reason declaration aligned with external files and private recovery."""
import copy
import importlib.util
from pathlib import Path
import plistlib
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("configuration", ROOT / "scripts/verify_configuration.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class PrivacyConfigurationTests(unittest.TestCase):
    def setUp(self):
        self.privacy = plistlib.loads((ROOT / "App/NoteHush/Resources/PrivacyInfo.xcprivacy").read_bytes())

    def testCurrentManifestAndReorderedReasonsPass(self):
        module.validate_privacy(self.privacy)
        self.privacy["NSPrivacyAccessedAPITypes"][0]["NSPrivacyAccessedAPITypeReasons"].reverse()
        module.validate_privacy(self.privacy)

    def testMissingWrongOrDuplicateReasonsFail(self):
        for reasons in [[], ["3B52.1"], ["C617.1"], ["3B52.1", "DDA9.1"], ["C617.1", "C617.1"]]:
            privacy = copy.deepcopy(self.privacy)
            privacy["NSPrivacyAccessedAPITypes"][0]["NSPrivacyAccessedAPITypeReasons"] = reasons
            with self.subTest(reasons=reasons), self.assertRaises(ValueError):
                module.validate_privacy(privacy)

    def testMissingDuplicateOrUnauditedCategoriesFail(self):
        accesses = self.privacy["NSPrivacyAccessedAPITypes"]
        for invalid in [[], accesses + accesses, [{"NSPrivacyAccessedAPIType": "unaudited"}]]:
            privacy = copy.deepcopy(self.privacy)
            privacy["NSPrivacyAccessedAPITypes"] = invalid
            with self.assertRaises(ValueError):
                module.validate_privacy(privacy)

    def testTrackingAndCollectionCannotChangeSilently(self):
        for key, value in [("NSPrivacyTracking", True), ("NSPrivacyTrackingDomains", ["example.invalid"]),
                           ("NSPrivacyCollectedDataTypes", [{}])]:
            privacy = copy.deepcopy(self.privacy)
            privacy[key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                module.validate_privacy(privacy)


if __name__ == "__main__":
    unittest.main()
