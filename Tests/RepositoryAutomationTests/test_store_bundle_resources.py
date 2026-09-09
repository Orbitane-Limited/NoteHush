"""Store export must preserve audited metadata and stop before low-space native work."""
import os
import plistlib
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "scripts"))
import app_store_checks as checks
import store_delivery as delivery


class StoreBundleResourcesTests(unittest.TestCase):
    def setUp(self):
        self.info = {
            "CFBundleIdentifier": checks.BUNDLE_ID, "CFBundleShortVersionString": "0.1.0",
            "CFBundleVersion": "1", "LSMinimumSystemVersion": "14.0",
            "NoteHushRequiresTestWorkspace": "NO", "NoteHushPerformanceBuild": "NO",
            "CFBundleExecutable": "NoteHush", "CFBundleIconName": "AppIcon",
            "CFBundleIconFile": "AppIcon", "ITSAppUsesNonExemptEncryption": False,
        }

    def testExportRequiresTheAuditedEncryptionBoolean(self):
        checks.validate_info(self.info, "0.1.0", "1")
        for value in (None, True, 0, "false", "NO"):
            with self.subTest(value=value), self.assertRaises(ValueError):
                checks.validate_info({**self.info, "ITSAppUsesNonExemptEncryption": value}, "0.1.0", "1")
        missing = dict(self.info)
        del missing["ITSAppUsesNonExemptEncryption"]
        with self.assertRaises(ValueError):
            checks.validate_info(missing, "0.1.0", "1")

    def testExportRequiresBothOriginalIconMetadataFields(self):
        for key in ("CFBundleIconName", "CFBundleIconFile"):
            for value in (None, "", "AnotherIcon", False):
                with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                    checks.validate_info({**self.info, key: value}, "0.1.0", "1")

    def testMissingEmptyDirectoryOrLinkedIconStopsBeforeSigningTools(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "Config").mkdir()
            (root / "Config/Version.xcconfig").write_text(
                "MARKETING_VERSION = 0.1.0\nCURRENT_PROJECT_VERSION = 1\n")
            source = root / "App/NoteHush/Resources"
            source.mkdir(parents=True)
            contents = root / "fixture.app/Contents"
            resources = contents / "Resources"
            resources.mkdir(parents=True)
            (contents / "Info.plist").write_bytes(plistlib.dumps(self.info))
            privacy = plistlib.dumps({"NSPrivacyTracking": False})
            (source / "PrivacyInfo.xcprivacy").write_bytes(privacy)
            (resources / "PrivacyInfo.xcprivacy").write_bytes(privacy)
            icon = resources / "AppIcon.icns"
            outside = root / "generated-icon"
            outside.write_bytes(b"generated fixture")
            for kind in ("missing", "empty", "directory", "symlink"):
                if kind == "empty":
                    icon.write_bytes(b"")
                elif kind == "directory":
                    icon.mkdir()
                elif kind == "symlink":
                    icon.symlink_to(outside)
                with self.subTest(kind=kind), \
                        mock.patch.object(checks, "command", side_effect=AssertionError("Native tool reached")) as native:
                    with self.assertRaisesRegex(ValueError, "icon"):
                        checks.verify_app(contents.parent, root, "ABCDEFGHIJ", "A" * 40, root)
                    native.assert_not_called()
                if icon.is_dir():
                    icon.rmdir()
                elif icon.exists() or icon.is_symlink():
                    icon.unlink()
            self.assertEqual(outside.read_bytes(), b"generated fixture")

    def testStorageFailurePrecedesSigningInputsAndNativeTools(self):
        with mock.patch.object(delivery, "verify_source", return_value="a" * 40), \
                mock.patch.object(delivery, "secret", side_effect=AssertionError("Signing input read")) as secret, \
                mock.patch.object(delivery, "native", side_effect=ValueError("storage insufficient")) as native:
            with self.assertRaisesRegex(ValueError, "storage insufficient"):
                delivery.deliver(mock.Mock())
        secret.assert_not_called()
        native.assert_called_once_with(["python3", "scripts/check_runner_storage.py"])

    def testStorageLossAfterArchiveOrExportStopsTheNextNativeStage(self):
        values = {
            "STORE_TEAM_ID": "ABCDEFGHIJ", "STORE_APP_CERTIFICATE_SHA1": "A" * 40,
            "STORE_INSTALLER_CERTIFICATE_SHA1": "B" * 40,
            "STORE_INSTALLER_CERTIFICATE_SHA256": "C" * 64,
            "STORE_CONFIRMED_BUNDLE_ID": checks.BUNDLE_ID, "STORE_API_KEY_ID": "ABCDEFGHIJ",
            "STORE_API_ISSUER_ID": "2430fc6e-a49b-4bff-bf70-340558c71fd7", "STORE_APP_ID": "123",
            "STORE_SIGNING_P12_BASE64": "Zml4dHVyZQ==", "STORE_PROFILE_BASE64": "Zml4dHVyZQ==",
            "STORE_API_KEY_BASE64": "Zml4dHVyZQ==", "STORE_SIGNING_P12_PASSWORD": "fixture",
        }
        for failing_check, forbidden in ((2, "-exportArchive"), (3, "--expand-full")):
            with self.subTest(failing_check=failing_check), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                assets = mock.Mock(directory=root / "owned-signing-fixture", keychain=root / "unused.keychain")
                assets.directory.mkdir()
                capacity_checks = 0
                calls = []

                def native(arguments):
                    nonlocal capacity_checks
                    calls.append(arguments)
                    if arguments == ["python3", "scripts/check_runner_storage.py"]:
                        capacity_checks += 1
                        if capacity_checks == failing_check:
                            raise ValueError("storage decreased")
                    if arguments[:2] == ["xcodebuild", "-version"]:
                        return b"Xcode 26.6\nBuild version fixture\n"
                    if arguments[:2] == ["security", "cms"]:
                        return plistlib.dumps({"UUID": "2430FC6E-A49B-4BFF-BF70-340558C71FD7"})
                    if arguments[:2] == ["security", "find-identity"]:
                        return ("A" * 40 + " " + "B" * 40).encode()
                    if "-exportArchive" in arguments:
                        export = Path(arguments[arguments.index("-exportPath") + 1])
                        export.mkdir()
                        (export / "fixture.pkg").write_bytes(b"generated package")
                    if arguments[:2] == ["pkgutil", "--check-signature"]:
                        return ("3rd Party Mac Developer Installer: fixture " + "C" * 64).encode()
                    return b""

                with mock.patch.object(delivery, "ROOT", root), \
                        mock.patch.object(delivery, "verify_source", return_value="a" * 40), \
                        mock.patch.object(delivery, "version_settings", return_value=("0.1.0", "1")), \
                        mock.patch.object(delivery, "secret", side_effect=values.__getitem__), \
                        mock.patch.object(delivery, "validate_profile"), \
                        mock.patch.object(delivery, "verify_app", return_value={}), \
                        mock.patch.object(delivery, "verify_no_quarantine"), \
                        mock.patch.object(delivery, "StoreConnect"), \
                        mock.patch.object(delivery, "native", side_effect=native), \
                        mock.patch.dict(os.environ, {"GITHUB_RUN_ID": "1", "GITHUB_RUN_ATTEMPT": "1"}):
                    with self.assertRaisesRegex(ValueError, "storage decreased"):
                        delivery.deliver(assets)
                self.assertEqual(capacity_checks, failing_check)
                self.assertTrue(any("archive" in call for call in calls))
                self.assertFalse(any(forbidden in call for call in calls))
                self.assertFalse(any("--upload-package" in call for call in calls))
                if failing_check == 3:
                    self.assertTrue(any("-exportArchive" in call for call in calls))


if __name__ == "__main__":
    unittest.main()
