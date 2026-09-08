"""Exercise credential cleanup and ownership on ordinary temporary fixtures."""
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "scripts"))
from store_delivery import SigningAssets, private_write

PROFILE_UUID = "2430FC6E-A49B-4BFF-BF70-340558C71FD7"


class SigningCleanupTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.commands = []
        self.fail_delete = False

        def run(command):
            self.commands.append(command)
            if command[1] == "list-keychains" and "-s" not in command:
                return f'"/fixture/login.keychain-db"\n"{self.assets.keychain}"\n"/fixture/new-user.keychain-db"\n'.encode()
            if command[1] == "delete-keychain":
                if self.fail_delete:
                    raise ValueError("injected deletion failure")
                self.assets.keychain.unlink()
            return b""

        self.assets = SigningAssets(self.root / "signing", self.root / "profiles", run)
        self.assets.create()
        private_write(self.assets.keychain, b"fixture keychain")
        private_write(self.assets.directory / "signing.p12", b"fixture certificate material")
        (self.assets.directory / "private_keys").mkdir()
        private_write(self.assets.directory / "private_keys/key.p8", b"fixture API material")
        self.profile = self.assets.directory / "profile.provisionprofile"
        private_write(self.profile, b"fixture provisioning profile")

    def tearDown(self):
        self.temporary.cleanup()

    def testFailureCleanupRemovesOnlyOwnedAssetsAndPreservesOtherKeychains(self):
        self.assets.install_profile(self.profile, PROFILE_UUID)
        installed = self.assets.profile_directory / f"{PROFILE_UUID}.provisionprofile"
        self.assertEqual(installed.stat().st_ino, self.profile.stat().st_ino)
        self.assets.cleanup()
        self.assertFalse(installed.exists())
        self.assertFalse(self.assets.directory.exists())
        self.assertIn(["security", "list-keychains", "-d", "user", "-s", "/fixture/login.keychain-db",
                       "/fixture/new-user.keychain-db"], self.commands)
        self.assets.cleanup()  # the workflow's always step is idempotent

    def testIdenticalPreexistingProfileIsReusedButNeverDeleted(self):
        self.assets.profile_directory.mkdir()
        installed = self.assets.profile_directory / f"{PROFILE_UUID}.provisionprofile"
        installed.write_bytes(self.profile.read_bytes())
        inode = installed.stat().st_ino
        self.assets.install_profile(self.profile, PROFILE_UUID)
        self.assets.cleanup()
        self.assertEqual(installed.stat().st_ino, inode)
        self.assertEqual(installed.read_bytes(), b"fixture provisioning profile")

    def testLowercaseProfileUUIDUsesCanonicalOwnedFilenameAndCleansUp(self):
        self.assets.install_profile(self.profile, PROFILE_UUID.lower())
        installed = self.assets.profile_directory / f"{PROFILE_UUID}.provisionprofile"
        self.assertEqual(installed.stat().st_ino, self.profile.stat().st_ino)
        state = json.loads((self.assets.directory / "profile.json").read_text())
        self.assertEqual(state["name"], installed.name)
        self.assets.cleanup()
        self.assertFalse(installed.exists())
        self.assertFalse(self.assets.directory.exists())

    def testInvalidProfileUUIDCannotPublishAnOwnershipRecord(self):
        for invalid in (None, 123, "-" * 36, PROFILE_UUID.replace("-", ""),
                        "{" + PROFILE_UUID + "}", "../" + PROFILE_UUID):
            with self.subTest(value=invalid), self.assertRaises(ValueError):
                self.assets.install_profile(self.profile, invalid)
            self.assertFalse((self.assets.directory / "profile.json").exists())
            self.assertFalse(self.assets.profile_directory.exists())
        self.assertEqual(self.commands, [])

    def testDifferentExistingOrSymlinkedProfileIsPreservedOnFailure(self):
        self.assets.profile_directory.mkdir()
        installed = self.assets.profile_directory / f"{PROFILE_UUID}.provisionprofile"
        external = self.root / "external"
        external.write_bytes(b"preexisting unrelated profile")
        installed.symlink_to(external)
        with self.assertRaises(ValueError):
            self.assets.install_profile(self.profile, PROFILE_UUID)
        self.assets.cleanup()
        self.assertTrue(installed.is_symlink())
        self.assertEqual(external.read_bytes(), b"preexisting unrelated profile")

    def testFailedKeychainDeletionStillRemovesPlaintextAndProfileThenCanRetry(self):
        self.assets.install_profile(self.profile, PROFILE_UUID)
        self.fail_delete = True
        with self.assertRaises(ValueError):
            self.assets.cleanup()
        self.assertTrue(self.assets.keychain.exists())
        self.assertTrue((self.assets.directory / "owner.json").exists())
        self.assertFalse((self.assets.directory / "signing.p12").exists())
        self.assertFalse((self.assets.directory / "private_keys").exists())
        self.assertFalse((self.assets.profile_directory / f"{PROFILE_UUID}.provisionprofile").exists())
        self.fail_delete = False
        self.assets.cleanup()
        self.assertFalse(self.assets.directory.exists())

    def testReplacedInstalledProfileIsPreserved(self):
        self.assets.install_profile(self.profile, PROFILE_UUID)
        installed = self.assets.profile_directory / f"{PROFILE_UUID}.provisionprofile"
        replacement = self.root / "replacement"
        replacement.write_bytes(b"new profile owned by someone else")
        os.replace(replacement, installed)
        self.assets.cleanup()
        self.assertEqual(installed.read_bytes(), b"new profile owned by someone else")

    def testStaleSearchEntryIsRemovedEvenIfKeychainWasAlreadyDeleted(self):
        self.assets.keychain.unlink()
        self.assets.cleanup()
        self.assertIn(["security", "list-keychains", "-d", "user", "-s", "/fixture/login.keychain-db",
                       "/fixture/new-user.keychain-db"], self.commands)
        self.assertFalse(any(command[1] == "delete-keychain" for command in self.commands))

    def testMalformedOwnershipCannotDeleteFilesOutsideTheRun(self):
        self.assets.install_profile(self.profile, PROFILE_UUID)
        state_path = self.assets.directory / "profile.json"
        state = json.loads(state_path.read_text())
        state["name"] = "../../other.provisionprofile"
        state_path.write_text(json.dumps(state))
        with self.assertRaises(ValueError):
            self.assets.cleanup()
        self.assertFalse((self.assets.directory / "signing.p12").exists())
        self.assertTrue(self.assets.directory.exists())


if __name__ == "__main__":
    unittest.main()
