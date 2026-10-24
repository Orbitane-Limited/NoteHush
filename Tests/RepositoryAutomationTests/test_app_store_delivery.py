"""Failure-safe and privacy-safe App Store delivery automation coverage."""

from datetime import datetime, timedelta, timezone
import json
import hashlib
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
import app_store_delivery as delivery  # noqa: E402


def valid_profile(expiration=None):
    return {
        "Name": delivery.PROFILE_NAME,
        "UUID": "11111111-2222-3333-4444-555555555555",
        "TeamIdentifier": [delivery.TEAM_ID],
        "ExpirationDate": expiration or datetime.now(timezone.utc) + timedelta(days=10),
        "Entitlements": {
            "application-identifier": f"{delivery.TEAM_ID}.{delivery.BUNDLE_ID}",
            "com.apple.developer.team-identifier": delivery.TEAM_ID,
            "get-task-allow": False,
            **delivery.EXPECTED_ENTITLEMENTS,
        },
    }


class AppStoreDeliveryTests(unittest.TestCase):
    def test_profile_is_pinned_to_team_app_entitlements_and_expiration(self):
        delivery.validate_profile(valid_profile())
        cases = [
            ({**valid_profile(), "Name": "wrong"}, "profile name"),
            ({**valid_profile(), "TeamIdentifier": ["wrong"]}, "different Apple team"),
            ({**valid_profile(), "Entitlements": {**valid_profile()["Entitlements"],
                                                   "application-identifier": "wrong.app"}},
             "application identifier"),
            (valid_profile(datetime.now(timezone.utc) - timedelta(seconds=1)), "expired"),
            ({**valid_profile(), "Entitlements": {**valid_profile()["Entitlements"],
                                                   "get-task-allow": True}}, "debugging"),
            ({**valid_profile(), "Entitlements": {k: v for k, v in valid_profile()["Entitlements"].items()
                                                   if k != "com.apple.security.print"}}, "entitlement"),
        ]
        for profile, message in cases:
            with self.subTest(message=message), self.assertRaisesRegex(delivery.DeliveryError, message):
                delivery.validate_profile(profile)

    def test_signing_certificates_and_profile_cert_are_exactly_pinned(self):
        app_cert = b"fixture-app-certificate"
        app_fingerprint = hashlib.sha1(app_cert).hexdigest().upper()
        identities = (f'1) {app_fingerprint} "{delivery.SIGNING_IDENTITY}"\n'
                      f'2) {delivery.INSTALLER_SHA1} "{delivery.INSTALLER_IDENTITY}"\n')
        profile = {"DeveloperCertificates": [app_cert]}
        with patch.object(delivery, "SIGNING_SHA1", app_fingerprint):
            delivery.validate_imported_certificates(identities, profile)
            with self.assertRaisesRegex(delivery.DeliveryError, "does not authorize"):
                delivery.validate_imported_certificates(identities, {"DeveloperCertificates": [b"other"]})
            with self.assertRaisesRegex(delivery.DeliveryError, "Installer Distribution"):
                delivery.validate_imported_certificates(
                    identities.replace(delivery.INSTALLER_SHA1, "0" * 40), profile)

    def test_asc_build_history_reads_all_pages_and_rejects_external_next_links(self):
        pages = [
            {"data": [{"id": "app-id"}]},
            {"data": [{"attributes": {"version": "3"}}],
             "links": {"next": "https://api.appstoreconnect.apple.com/v1/builds?page=2"}},
            {"data": [{"attributes": {"version": "12"}}]},
        ]
        with patch.object(delivery, "asc_get", side_effect=pages) as get:
            self.assertEqual(delivery.prior_builds(), [3, 12])
            self.assertEqual(get.call_count, 3)
        with patch.object(delivery, "asc_token", return_value="fixture-token"):
            with self.assertRaisesRegex(delivery.DeliveryError, "untrusted URL"):
                delivery.asc_get("https://example.org/steal-token")

    def test_asc_jwt_signs_with_key_from_the_run_isolated_api_home(self):
        with tempfile.TemporaryDirectory() as temporary:
            key_path = Path(temporary) / ".appstoreconnect/private_keys/AuthKey_ABCDEF1234.p8"
            key_path.parent.mkdir(parents=True)
            key_path.write_text("private key fixture")
            process_result = subprocess.CompletedProcess([], 0, stdout=b"\x30\x06\x02\x01\x01\x02\x01\x01",
                                                         stderr=b"")
            with patch.object(delivery, "read_api_key", return_value=(
                    {"kid": "ABCDEF1234", "iss": "11111111-2222-3333-4444-555555555555"},
                    b"fixture")), \
                    patch.object(delivery, "load_manifest", return_value=(Path("manifest"), {
                        "api_home": temporary,
                    })), patch.object(delivery, "command", return_value=process_result) as command:
                token = delivery.asc_token()
            self.assertEqual(len(token.split(".")), 3)
            self.assertEqual(command.call_args.args[0][-1], str(key_path))

    def test_cleanup_only_removes_manifest_owned_assets(self):
        with tempfile.TemporaryDirectory() as temporary:
            runner_temp = Path(temporary)
            work = runner_temp / "notehush-app-store-test"
            work.mkdir()
            user_home = runner_temp / "user-home"
            user_home.mkdir()
            keychain = work / "notehush.keychain-db"
            keychain.write_text("owned")
            profile = runner_temp / "existing-user-profile.provisionprofile"
            profile.write_text("unrelated")
            owned_profile = user_home / "Library/MobileDevice/Provisioning Profiles"
            owned_profile.mkdir(parents=True)
            owned_profile = owned_profile / "11111111-2222-3333-4444-555555555555.provisionprofile"
            owned_profile.write_text("owned")
            manifest = {
                "schema": 1,
                "owner": "NoteHush App Store delivery",
                "work_directory": str(work),
                "user_home": str(user_home),
                "api_home": str(work / "api-home"),
                "keychain_path": str(keychain),
                "profile_path": str(owned_profile),
                "profile_uuid": "11111111-2222-3333-4444-555555555555",
                "profile_sha256": hashlib.sha256(b"owned").hexdigest(),
                "original_keychain_search_list": ["login.keychain-db"],
            }
            manifest_path = runner_temp / delivery.MANIFEST_NAME
            manifest_path.write_text(json.dumps(manifest))
            with patch.dict(os.environ, {"RUNNER_TEMP": str(runner_temp)}), \
                    patch.object(delivery.Path, "home", return_value=user_home), \
                    patch.object(delivery, "command") as command:
                delivery.cleanup()
            self.assertFalse(work.exists())
            self.assertFalse(manifest_path.exists())
            self.assertTrue(profile.exists())
            self.assertEqual(command.call_count, 2)

    def test_cleanup_refuses_manifest_with_unowned_paths(self):
        with tempfile.TemporaryDirectory() as temporary:
            runner_temp = Path(temporary)
            unrelated = runner_temp / "notehush-app-store-do-not-delete"
            unrelated.mkdir()
            manifest_path = runner_temp / delivery.MANIFEST_NAME
            manifest_path.write_text(json.dumps({
                "schema": 1, "owner": "other tool", "work_directory": str(unrelated),
            }))
            with patch.dict(os.environ, {"RUNNER_TEMP": str(runner_temp)}):
                with self.assertRaisesRegex(delivery.DeliveryError, "ownership validation"):
                    delivery.cleanup()
            self.assertTrue(unrelated.exists())
            self.assertTrue(manifest_path.exists())

    def test_cleanup_failure_preserves_manifest_and_owned_files_for_recovery(self):
        with tempfile.TemporaryDirectory() as temporary:
            runner_temp = Path(temporary)
            work = runner_temp / "notehush-app-store-recovery"
            work.mkdir()
            user_home = runner_temp / "user-home"
            user_home.mkdir()
            keychain = work / "notehush.keychain-db"
            keychain.write_text("owned")
            profile = user_home / "Library/MobileDevice/Provisioning Profiles"
            profile.mkdir(parents=True)
            profile = profile / "11111111-2222-3333-4444-555555555555.provisionprofile"
            profile.write_text("owned")
            manifest_path = runner_temp / delivery.MANIFEST_NAME
            manifest_path.write_text(json.dumps({
                "schema": 1,
                "owner": "NoteHush App Store delivery",
                "work_directory": str(work),
                "user_home": str(user_home),
                "api_home": str(work / "api-home"),
                "keychain_path": str(keychain),
                "profile_path": str(profile),
                "profile_uuid": profile.stem,
                "profile_sha256": hashlib.sha256(b"owned").hexdigest(),
                "original_keychain_search_list": ["login.keychain-db"],
            }))
            with patch.dict(os.environ, {"RUNNER_TEMP": str(runner_temp)}), \
                    patch.object(delivery.Path, "home", return_value=user_home), \
                    patch.object(delivery, "command", side_effect=delivery.DeliveryError("cleanup injected")):
                with self.assertRaisesRegex(delivery.DeliveryError, "cleanup injected"):
                    delivery.cleanup()
            self.assertTrue(work.exists())
            self.assertTrue(keychain.exists())
            self.assertTrue(profile.exists())
            self.assertTrue(manifest_path.exists())

    def test_command_failure_redacts_tool_output(self):
        class FakeProcess:
            returncode = 17

            def communicate(self, input=None):
                del input
                return b"TOP-SECRET-OUTPUT", None

        with tempfile.TemporaryDirectory() as temporary:
            log_path = Path(temporary) / "delivery.log"
            with patch.dict(os.environ, {"NOTEHUSH_APP_STORE_LOG": str(log_path),
                                         "MAC_APP_DISTRIBUTION_P12_PASSWORD": "TOP-SECRET-OUTPUT"}), \
                    patch.object(delivery.subprocess, "Popen", return_value=FakeProcess()):
                with self.assertRaises(delivery.DeliveryError) as raised:
                    delivery.command(["/fake/signer"])
            self.assertNotIn("TOP-SECRET-OUTPUT", str(raised.exception))
            self.assertNotIn("TOP-SECRET-OUTPUT", log_path.read_text())
            self.assertIn("[REDACTED]", log_path.read_text())
            self.assertIn("exit 17", str(raised.exception))

    def test_signing_secrets_are_not_inherited_by_external_processes(self):
        captured = {}

        class FakeProcess:
            returncode = 0

            def communicate(self, input=None):
                del input
                return b"ok", b""

        def fake_popen(args, **kwargs):
            del args
            captured.update(kwargs)
            return FakeProcess()

        with tempfile.TemporaryDirectory() as temporary, patch.dict(os.environ, {
                "MAC_APP_DISTRIBUTION_P12_PASSWORD": "fixture-password",
                "ASC_PRIVATE_KEY_BASE64": "fixture-private-key",
                "ASC_KEY_ID": "ABCDEF1234",
                "NOTEHUSH_APP_STORE_LOG": str(Path(temporary) / "delivery.log"),
        }), patch.object(delivery.subprocess, "Popen", side_effect=fake_popen):
            delivery.command(["/fake/signer"])
        self.assertNotIn("MAC_APP_DISTRIBUTION_P12_PASSWORD", captured["env"])
        self.assertNotIn("ASC_PRIVATE_KEY_BASE64", captured["env"])
        self.assertNotIn("ASC_KEY_ID", captured["env"])
        self.assertTrue(captured["start_new_session"])

    def test_cancellation_terminates_process_group_then_force_kills_if_needed(self):
        class FakeProcess:
            pid = 4321

            def __init__(self, wait_results):
                self.wait_results = iter(wait_results)

            def poll(self):
                return None

            def wait(self, timeout=None):
                result = next(self.wait_results)
                if isinstance(result, BaseException):
                    raise result
                return result

        for wait_results, expected_signals in [
                ([0], [delivery.signal.SIGTERM]),
                ([subprocess.TimeoutExpired("fixture", 10), 0],
                 [delivery.signal.SIGTERM, delivery.signal.SIGKILL]),
        ]:
            with self.subTest(expected_signals=expected_signals):
                child = FakeProcess(wait_results)
                handlers = {}

                def set_handler(signum, handler):
                    previous = handlers.get(signum)
                    handlers[signum] = handler
                    return previous

                with patch.object(delivery, "ACTIVE_CHILD", child), \
                        patch.object(delivery.signal, "signal", side_effect=set_handler), \
                        patch.object(delivery.os, "killpg") as killpg:
                    with self.assertRaises(SystemExit):
                        with delivery.child_process_guard():
                            handlers[delivery.signal.SIGTERM](delivery.signal.SIGTERM, None)
                self.assertEqual([call.args[1] for call in killpg.call_args_list], expected_signals)

    def test_workflow_guards_main_manual_upload_and_never_exposes_secrets_to_prs(self):
        workflow = (ROOT / ".github/workflows/app-store-delivery.yml").read_text()
        self.assertIn("workflow_dispatch:", workflow)
        self.assertIn("default: false", workflow)
        self.assertIn("github.ref == 'refs/heads/main' && inputs.confirm_upload == true", workflow)
        self.assertIn("name: app-store", workflow)
        self.assertNotIn("pull_request:", workflow)
        self.assertIn("persist-credentials: false", workflow)
        steps = {}
        lines = workflow.splitlines()
        for index, line in enumerate(lines):
            if line.startswith("      - name: "):
                end = index + 1
                while end < len(lines) and not lines[end].startswith("      - name: "):
                    end += 1
                steps[line.partition(":")[2].strip()] = "\n".join(lines[index:end])
        self.assertIn("scripts/app_store_delivery.py stage", steps["Create and verify signed candidate"])
        artifact_index = list(steps).index("Upload the signed package and checksum")
        upload_index = list(steps).index("Upload verified package to App Store Connect")
        self.assertLess(artifact_index, upload_index)
        asc_upload = steps["Upload verified package to App Store Connect"]
        self.assertIn("ASC_PRIVATE_KEY_BASE64", asc_upload)
        self.assertNotIn("ASC_PRIVATE_KEY_BASE64", steps["Run the complete release validation at this exact commit"])
        self.assertNotIn("ASC_PRIVATE_KEY_BASE64", steps["Create and verify signed candidate"])
        self.assertIn("scripts/app_store_delivery.py upload", asc_upload)
        self.assertIn("if: always()", workflow)
        self.assertIn("scripts/app_store_delivery.py cleanup", workflow)


if __name__ == "__main__":
    unittest.main()
