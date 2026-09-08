"""Distribution gates must reject plausible but invalid release evidence."""
import copy
import base64
from datetime import datetime, timedelta, timezone
import hashlib
import json
import os
from pathlib import Path
import platform
import sys
import subprocess
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "scripts"))
import app_store_checks as checks
from store_connect import StoreConnect, jose_signature, make_token


class AppStoreChecksTests(unittest.TestCase):
    def setUp(self):
        self.team = "ABCDEFGHIJ"
        self.app_id = self.team + "." + checks.BUNDLE_ID
        self.certificate = b"isolated certificate fixture"
        self.fingerprint = hashlib.sha1(self.certificate).hexdigest().upper()
        self.profile = {
            "UUID": "2430FC6E-A49B-4BFF-BF70-340558C71FD7", "Platform": ["OSX"],
            "TeamIdentifier": [self.team], "ApplicationIdentifierPrefix": [self.team],
            "ExpirationDate": datetime.now(timezone.utc) + timedelta(days=1),
            "DeveloperCertificates": [self.certificate], "Entitlements": {
                "com.apple.application-identifier": self.app_id,
                "com.apple.developer.team-identifier": self.team, "beta-reports-active": True,
            },
        }
        self.entitlements = {**checks.PRODUCT_ENTITLEMENTS,
                             **self.profile["Entitlements"]}

    def testStoreProfileAndExactProductPermissions(self):
        self.assertEqual(checks.validate_profile(self.profile, self.team, self.fingerprint), self.app_id)
        checks.validate_entitlements(self.entitlements, self.team, self.app_id, self.profile)
        del self.entitlements["beta-reports-active"]
        checks.validate_entitlements(self.entitlements, self.team, self.app_id, self.profile)

    def testSignatureRequirementIsAcceptedByNativeCompiler(self):
        # Exercise Apple's actual requirement parser without a signing identity.
        # codesign and csreq share the literal-versus-filename input convention.
        compiled_requirements = []

        def compile_requirement(arguments):
            requirement = arguments[arguments.index("-R") + 1]
            result = subprocess.run(["/usr/bin/csreq", "-r", requirement, "-t"],
                                    capture_output=True, env=checks.tool_environment(), timeout=30)
            self.assertEqual(result.returncode, 0,
                             "The actual native requirement parser rejected the verifier's input")
            compiled_requirements.append(result.stdout)
            return b""

        with mock.patch.object(checks, "command", side_effect=compile_requirement):
            checks.verify_code_signature(Path("generated-fixture.app"), self.team)
        self.assertEqual(len(compiled_requirements), 1)
        self.assertIn(b"anchor apple generic", compiled_requirements[0])
        self.assertIn(b"certificate leaf[subject.OU]", compiled_requirements[0])
        self.assertIn(self.team.encode(), compiled_requirements[0])

    def testSignatureRequirementRejectsMalformedTeamsBeforeNativeAccess(self):
        for team in (None, "", "ABCDEFGHI", "ABCDEFGHIJK", "abcdefghij", 'AAAA\" or true',
                     "ABCDEFGHIJ\n", "ABCDEFGHIJ/../../fixture"):
            with self.subTest(team=team), mock.patch.object(checks, "command") as command:
                with self.assertRaises(ValueError):
                    checks.verify_code_signature(Path("generated-fixture.app"), team)
                command.assert_not_called()

    def testNativeCertificateExtractionNeedsNoPrivateSigningCredential(self):
        # The installed Apple tool already has a public signature. Read it with
        # the production extraction path; do not sign or modify system code.
        with tempfile.TemporaryDirectory() as directory:
            certificate = checks.extract_signing_certificate(
                Path("/usr/bin/codesign"), platform.machine(), Path(directory))
            parsed = subprocess.run(["/usr/bin/openssl", "x509", "-inform", "DER", "-noout"],
                                    input=certificate, capture_output=True,
                                    env=checks.tool_environment(), timeout=30)
            self.assertEqual(parsed.returncode, 0, "Extracted leaf must be a real X.509 certificate")

    def testWrongExpiredDevelopmentAndWildcardProfilesFail(self):
        for field, value in [
            ("TeamIdentifier", ["WRONGTEAM1"]), ("Platform", ["iOS"]),
            ("ExpirationDate", datetime.now(timezone.utc) - timedelta(seconds=1)),
            ("ProvisionedDevices", []), ("ProvisionsAllDevices", True),
            ("DeveloperCertificates", [b"different certificate"]), ("UUID", "invalid"),
        ]:
            profile = copy.deepcopy(self.profile)
            profile[field] = value
            with self.subTest(field=field), self.assertRaises(ValueError):
                checks.validate_profile(profile, self.team, self.fingerprint)
        for field, value in [("com.apple.application-identifier", self.team + ".*"),
                             ("get-task-allow", True), ("com.apple.security.get-task-allow", True)]:
            profile = copy.deepcopy(self.profile)
            profile["Entitlements"][field] = value
            with self.subTest(field=field), self.assertRaises(ValueError):
                checks.validate_profile(profile, self.team, self.fingerprint)

    def testExtraMissingOrNonBooleanPermissionsFail(self):
        for key in checks.PRODUCT_ENTITLEMENTS:
            for value in (None, False, 1):
                actual = {**self.entitlements, key: value}
                with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                    checks.validate_entitlements(actual, self.team, self.app_id, self.profile)
        for key, value in [("com.apple.security.network.client", True),
                           ("com.apple.security.get-task-allow", False),
                           ("com.apple.security.temporary-exception.files.absolute-path.read-only", []),
                           ("keychain-access-groups", [self.app_id])]:
            with self.subTest(key=key), self.assertRaises(ValueError):
                checks.validate_entitlements({**self.entitlements, key: value},
                                            self.team, self.app_id, self.profile)

    def testBuildsMustIncreaseAcrossEveryPriorVersionAndState(self):
        builds = [{"type": "builds", "id": "1", "attributes": {"version": "2"}},
                  {"type": "builds", "id": "2", "attributes": {"version": "10", "expired": True}}]
        self.assertEqual(checks.validate_build_numbers("11", builds), 10)
        self.assertEqual(checks.validate_build_numbers("1", []), 0)
        for number in ("1", "2", "10", "0", "01", "1.0", 12, True):
            with self.subTest(number=number), self.assertRaises(ValueError):
                checks.validate_build_numbers(number, builds)
        for invalid in [builds + [builds[0]], [{"type": "builds", "id": "1", "attributes": {}}]]:
            with self.assertRaises(ValueError):
                checks.validate_build_numbers("12", invalid)

    def testCompleteMainCIRequired(self):
        revision = "a" * 40
        run = {"head_sha": revision, "head_branch": "main", "event": "push",
               "path": ".github/workflows/ci.yml", "status": "completed", "conclusion": "success",
               "repository": {"full_name": "Orbitane-Limited/NoteHush"}}
        checks.validate_ci(run, revision, "Orbitane-Limited/NoteHush")
        for key, value in [("head_sha", "b" * 40), ("head_branch", "issue-14/candidate"),
                           ("event", "pull_request"), ("path", ".github/workflows/delivery.yml"),
                           ("status", "in_progress"), ("conclusion", "failure")]:
            with self.subTest(key=key), self.assertRaises(ValueError):
                checks.validate_ci({**run, key: value}, revision, "Orbitane-Limited/NoteHush")

    def testMissingOrSelfApprovedEnvironmentCannotAuthorizeSigning(self):
        environment = {"name": "app-store", "protection_rules": [{"type": "required_reviewers",
                       "prevent_self_review": True, "reviewers": [{"type": "User"}]}]}
        checks.validate_environment(environment)
        for field, value in [("reviewers", []), ("prevent_self_review", False)]:
            invalid = copy.deepcopy(environment)
            invalid["protection_rules"][0][field] = value
            with self.assertRaises(ValueError):
                checks.validate_environment(invalid)
        with self.assertRaises(ValueError):
            checks.validate_environment({"name": "app-store", "protection_rules": []})

    def testJWTSignatureConversionWithPaddedAndShortIntegers(self):
        # Known unsigned values: high-bit R requires a DER sign byte; S is one.
        r = b"\x80" + b"\x11" * 31
        der = b"\x30\x26\x02\x21\x00" + r + b"\x02\x01\x01"
        self.assertEqual(jose_signature(der), r + b"\x00" * 31 + b"\x01")
        for invalid in [der[:-1], der + b"\x00", b"\x30\x06\x02\x01\x80\x02\x01\x01",
                        b"\x30\x07\x02\x02\x00\x01\x02\x01\x01"]:
            with self.assertRaises(ValueError):
                jose_signature(invalid)

    def testPaginationChecksOldestBuildAndFailsOnRepeatedPage(self):
        client = StoreConnect(Path("unused"), "ABCDEFGHIJ", "unused", "123")
        first = "https://api.appstoreconnect.apple.com/v1/apps/123/builds?limit=200&fields%5Bbuilds%5D=version"
        second = "https://api.appstoreconnect.apple.com/v1/apps/123/builds?cursor=page2"
        pages = {
            "https://api.appstoreconnect.apple.com/v1/apps/123": {"data": {
                "type": "apps", "id": "123", "attributes": {"bundleId": checks.BUNDLE_ID}}},
            first: {"data": [{"type": "builds", "id": "a", "attributes": {"version": "2"}}],
                    "links": {"next": second}},
            second: {"data": [{"type": "builds", "id": "b", "attributes": {"version": "9"}}],
                     "links": {"next": None}},
        }
        client.get = pages.__getitem__
        with self.assertRaises(ValueError):
            client.check_next_build("5")
        self.assertEqual(client.check_next_build("10"), 9)
        pages[second]["links"]["next"] = first
        with self.assertRaises(ValueError):
            client.check_next_build("10")

    def testUntrustedPaginationCannotReceiveCredentials(self):
        client = StoreConnect(Path("unused"), "ABCDEFGHIJ", "unused", "123")
        for url in ["https://example.invalid/v1/apps/123/builds",
                    "http://api.appstoreconnect.apple.com/v1/apps/123/builds",
                    "https://api.appstoreconnect.apple.com/v1/apps/999/builds"]:
            with self.assertRaises(ValueError):
                client.get(url)

    def testRealOpenSSLVerifiesTheGeneratedJWTAndItsBoundedScope(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            key, public = root / "fixture.p8", root / "fixture-public.pem"
            subprocess.run(["/usr/bin/openssl", "ecparam", "-name", "prime256v1", "-genkey", "-noout",
                            "-out", str(key)], check=True, capture_output=True)
            os.chmod(key, 0o600)
            subprocess.run(["/usr/bin/openssl", "pkey", "-in", str(key), "-pubout", "-out", str(public)],
                           check=True, capture_output=True)
            token = make_token(key, "ABCDEFGHIJ", "2430fc6e-a49b-4bff-bf70-340558c71fd7", "123")
            header, payload, signature = token.split(".")
            claims = json.loads(base64.urlsafe_b64decode(payload + "=" * (-len(payload) % 4)))
            self.assertEqual(claims["exp"] - claims["iat"], 300)
            self.assertEqual(claims["scope"], ["GET /v1/apps/123", "GET /v1/apps/123/builds"])
            raw = base64.urlsafe_b64decode(signature + "=" * (-len(signature) % 4))
            self.assertEqual(len(raw), 64)
            # Independent verifier consumes DER, not the producer's conversion.
            integers = []
            for value in (raw[:32], raw[32:]):
                value = value.lstrip(b"\x00") or b"\x00"
                if value[0] >= 128:
                    value = b"\x00" + value
                integers.append(b"\x02" + bytes([len(value)]) + value)
            encoded = b"".join(integers)
            (root / "signature.der").write_bytes(b"\x30" + bytes([len(encoded)]) + encoded)
            verified = subprocess.run(["/usr/bin/openssl", "dgst", "-sha256", "-verify", str(public),
                                       "-signature", str(root / "signature.der")],
                                      input=(header + "." + payload).encode(), capture_output=True)
            self.assertEqual(verified.returncode, 0)

    def testChildToolsDoNotInheritSigningSecretsOrGitHubCredentials(self):
        with mock.patch.dict(os.environ, {"STORE_SIGNING_P12_PASSWORD": "fixture password",
                                          "STORE_API_KEY_BASE64": "fixture key", "GH_TOKEN": "fixture token",
                                          "GITHUB_TOKEN": "fixture token", "DEVELOPER_DIR": "/fixture/Xcode"}):
            environment = checks.tool_environment()
        self.assertFalse(any(key.startswith("STORE_") for key in environment))
        self.assertNotIn("GH_TOKEN", environment)
        self.assertNotIn("GITHUB_TOKEN", environment)
        self.assertEqual(environment["DEVELOPER_DIR"], "/fixture/Xcode")

    def testChildEnvironmentContainsOnlyDeclaredToolInputs(self):
        permitted = {"PATH": "/usr/bin:/bin", "HOME": "/fixture/home", "TMPDIR": "/fixture/tmp",
                     "USER": "fixture", "LOGNAME": "fixture", "DEVELOPER_DIR": "/fixture/Xcode",
                     "LANG": "en_US.UTF-8", "__CF_USER_TEXT_ENCODING": "0x1F5:0:0"}
        unrelated = {"UNRELATED_SERVICE_TOKEN": "fixture token", "AWS_SECRET_ACCESS_KEY": "fixture key",
                     "ACTIONS_RUNTIME_TOKEN": "fixture token", "API_PRIVATE_KEYS_DIR": "/unreviewed/keys",
                     "PYTHONPATH": "/unreviewed/python", "DYLD_LIBRARY_PATH": "/unreviewed/libraries",
                     "XCODE_XCCONFIG_FILE": "/unreviewed/config", "TOOLCHAINS": "unreviewed-toolchain",
                     "SDKROOT": "/unreviewed/sdk", "LC_ALL": "fixture-locale"}
        with mock.patch.dict(os.environ, {**permitted, **unrelated}, clear=True):
            self.assertEqual(checks.tool_environment(), {**permitted, "LC_ALL": "C"})
        with mock.patch.dict(os.environ, {}, clear=True):
            self.assertEqual(checks.tool_environment(), {"LC_ALL": "C"})

    def testNativeVerifierChildCannotReadUnrelatedParentCredential(self):
        # A real, harmless child verifies the subprocess boundary. Only a fixed
        # success marker is returned; neither parent nor child prints values.
        program = ("import os; "
                   "assert 'UNRELATED_SERVICE_TOKEN' not in os.environ; "
                   "assert os.environ['LC_ALL'] == 'C'; print('verified')")
        with mock.patch.dict(os.environ, {"UNRELATED_SERVICE_TOKEN": "generated fixture credential"}):
            self.assertEqual(checks.command([sys.executable, "-c", program]), b"verified\n")


if __name__ == "__main__":
    unittest.main()
