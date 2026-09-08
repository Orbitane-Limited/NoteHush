"""The second source preflight runs while signing inputs exist in its parent."""
import os
from pathlib import Path
import subprocess
import sys
import unittest
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "scripts"))
import store_preflight as preflight


class StorePreflightEnvironmentTests(unittest.TestCase):
    def testGitHubChildReceivesOnlyItsExplicitWorkflowToken(self):
        parent = {"PATH": "/fixture/bin", "GH_TOKEN": "fixture workflow token",
                  "STORE_API_KEY_BASE64": "fixture signing key",
                  "UNRELATED_SERVICE_TOKEN": "fixture unrelated token", "GH_HOST": "unreviewed.invalid"}
        result = subprocess.CompletedProcess([], 0, stdout=b'{"verified":true}')
        with mock.patch.dict(os.environ, parent, clear=True), \
                mock.patch.object(preflight.subprocess, "run", return_value=result) as child:
            self.assertEqual(preflight.github("git/ref/heads/main"), {"verified": True})
        self.assertEqual(child.call_args.kwargs.get("env"),
                         {"PATH": "/fixture/bin", "LC_ALL": "C", "GH_TOKEN": "fixture workflow token"})
        self.assertEqual(child.call_args.kwargs.get("timeout"), 60)

    def testMissingWorkflowTokenCannotFallBackToLoggedInAccount(self):
        result = subprocess.CompletedProcess([], 0, stdout=b'{}')
        with mock.patch.dict(os.environ, {}, clear=True), \
                mock.patch.object(preflight.subprocess, "run", return_value=result) as child:
            with self.assertRaises(ValueError):
                preflight.github("git/ref/heads/main")
        child.assert_not_called()

    def testLocalGitChildrenReceiveNoWorkflowOrSigningCredentials(self):
        revision = "a" * 40
        parent = {"GITHUB_REPOSITORY": preflight.REPOSITORY, "GITHUB_EVENT_NAME": "workflow_dispatch",
                  "GITHUB_REF": "refs/heads/main", "GITHUB_SHA": revision, "NOTEHUSH_CI_RUN_ID": "123",
                  "PATH": "/fixture/bin", "GH_TOKEN": "fixture workflow token",
                  "STORE_SIGNING_P12_PASSWORD": "fixture password", "GIT_CONFIG_COUNT": "1"}
        with mock.patch.dict(os.environ, parent, clear=True), \
                mock.patch.object(preflight.subprocess, "check_output",
                                  side_effect=[revision.encode() + b"\n", b""]) as child, \
                mock.patch.object(preflight, "github", return_value={"object": {"sha": revision}}), \
                mock.patch.object(preflight, "validate_ci"), \
                mock.patch.object(preflight, "validate_environment"):
            self.assertEqual(preflight.verify(), revision)
        self.assertEqual(child.call_count, 2)
        for call in child.call_args_list:
            self.assertEqual(call.kwargs.get("env"), {"PATH": "/fixture/bin", "LC_ALL": "C"})
            self.assertEqual(call.kwargs.get("timeout"), 30)


if __name__ == "__main__":
    unittest.main()
