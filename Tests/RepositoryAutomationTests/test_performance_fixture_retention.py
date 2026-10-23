"""Run the real shell control flow with fake native tools and owned temporary data."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]

FAKE_NATIVE = r'''
set -euo pipefail
root="$FIXTURE_TEST_ROOT"
manifest="$root/$FIXTURE_TEST_MANIFEST"
name="${0##*/}"
case "$name" in
    PerformanceFixtureHarness) stage="$1" ;;
    python3) stage="${1##*/}" ;;
    xcrun) stage="metrics-$2" ;;
    *) stage="$name" ;;
esac
# Stages are fixed command names from the copied scripts, never document data.
printf '"%s"\n' "$stage" >> "$root/calls.jsonl"
if [[ "$stage" == prepare || "$stage" == prepare-interactions ]]; then
    [[ ! -e "$manifest" ]] || exit 73
fi
if [[ "$stage" == "$FAIL_STAGE" ]]; then
    exit "$FAIL_STATUS"
fi
if [[ "$name" == swift && " $* " == *' --show-bin-path '* ]]; then
    printf '%s\n' "$root/fake-bin"
elif [[ "$stage" == prepare || "$stage" == prepare-interactions ]]; then
    printf '%s' 'generated fixture manifest' > "$manifest"
    printf '%s' 'original generated recovery evidence' > "$root/generated-recovery"
elif [[ "$stage" == cleanup ]]; then
    rm "$manifest" "$root/generated-recovery"
fi
'''


class PerformanceFixtureRetentionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # Reuse one immutable fake executable. Each scenario still owns its
        # manifest, recovery bytes, call journal, environment and command links.
        temporary = tempfile.TemporaryDirectory()
        cls.addClassCleanup(temporary.cleanup)
        cls.fake_command = Path(temporary.name) / 'fake-command'
        cls.fake_command.write_text('#!/bin/bash\n' + FAKE_NATIVE)
        cls.fake_command.chmod(0o700)

    def run_script(self, script, failure=None, status=7, existing=False):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        (root / 'scripts').mkdir()
        (root / 'build/logs').mkdir(parents=True)
        (root / 'fake-bin').mkdir()
        shutil.copyfile(ROOT / 'scripts' / script, root / 'scripts' / script)
        helper = ROOT / 'scripts/performance_fixture_exit.sh'
        if helper.exists():
            shutil.copyfile(helper, root / 'scripts' / helper.name)
        (root / 'scripts/build_performance.sh').write_text('#!/bin/bash\nexit 0\n')
        for name in ['swift', 'python3', 'xcodebuild', 'xcrun', 'PerformanceFixtureHarness']:
            path = root / 'fake-bin' / name
            path.symlink_to(self.fake_command)
        manifest_name = ('build/interaction-fixtures.json' if script == 'test_interactions.sh'
                         else 'build/performance-fixtures.json')
        manifest = root / manifest_name
        evidence = root / 'generated-recovery'
        if existing:
            manifest.write_text('prior generated manifest')
            evidence.write_bytes(b'prior generated evidence')
        environment = {key: os.environ[key] for key in
                       ('HOME', 'TMPDIR', 'USER', 'LOGNAME', 'LANG', 'LC_ALL')
                       if key in os.environ}
        environment.update(PATH=f"{root / 'fake-bin'}:/usr/bin:/bin",
                           FIXTURE_TEST_ROOT=str(root), FIXTURE_TEST_MANIFEST=manifest_name,
                           FAIL_STAGE=failure or '', FAIL_STATUS=str(status))
        result = subprocess.run(['/bin/bash', str(root / 'scripts' / script)], env=environment,
                                capture_output=True, text=True, timeout=10)
        calls = [json.loads(line) for line in (root / 'calls.jsonl').read_text().splitlines()]
        return result, calls, manifest, evidence

    def assert_retained_failure(self, script, stage, status=7):
        result, calls, manifest, evidence = self.run_script(script, stage, status)
        self.assertEqual(result.returncode, status, result.stderr)
        self.assertNotIn('cleanup', calls)
        self.assertTrue(manifest.is_file())
        self.assertEqual(evidence.read_bytes(), b'original generated recovery evidence')

    def testLaunchTestAndAllPostProcessingFailuresRetainOriginalFixtures(self):
        for script in ['test_performance.sh', 'test_interactions.sh']:
            for stage in ['performance_environment.py', 'xcodebuild', 'verify_test_app.py',
                          'verify', 'metrics-export', 'metrics-get', 'summarize_performance.py']:
                with self.subTest(script=script, stage=stage):
                    self.assert_retained_failure(script, stage)

    def testProfileAndPostProfileVerificationFailuresRetainOriginalFixtures(self):
        for stage in ['performance_environment.py', 'profile', 'verify_test_app.py']:
            with self.subTest(stage=stage):
                self.assert_retained_failure('profile_performance.sh', stage)

    def testInterruptedExitStatusIsPreservedWithoutCleanup(self):
        for script in ['test_performance.sh', 'test_interactions.sh']:
            for status in [130, 143]:
                with self.subTest(script=script, status=status):
                    self.assert_retained_failure(script, 'xcodebuild', status)

    def testCompleteSuccessCleansExactlyOnceAfterLastVerification(self):
        for script, final_stage in [('test_performance.sh', 'summarize_performance.py'),
                                    ('test_interactions.sh', 'summarize_performance.py'),
                                    ('profile_performance.sh', 'verify_test_app.py')]:
            result, calls, manifest, evidence = self.run_script(script)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(calls[-2:], [final_stage, 'cleanup'])
            self.assertEqual(calls.count('cleanup'), 1)
            self.assertFalse(manifest.exists())
            self.assertFalse(evidence.exists())

    def testFailedSuccessPathCleanupFailsAndRetainsEvidence(self):
        for script in ['test_performance.sh', 'profile_performance.sh', 'test_interactions.sh']:
            result, calls, manifest, evidence = self.run_script(script, 'cleanup', 9)
            self.assertEqual(result.returncode, 9, result.stderr)
            self.assertEqual(calls.count('cleanup'), 1)
            self.assertTrue(manifest.is_file())
            self.assertEqual(evidence.read_bytes(), b'original generated recovery evidence')

    def testFailedAcquisitionCannotCleanPreviouslyOwnedEvidence(self):
        for script in ['test_performance.sh', 'profile_performance.sh', 'test_interactions.sh']:
            result, calls, manifest, evidence = self.run_script(script, existing=True)
            self.assertEqual(result.returncode, 73, result.stderr)
            self.assertNotIn('cleanup', calls)
            self.assertEqual(manifest.read_text(), 'prior generated manifest')
            self.assertEqual(evidence.read_bytes(), b'prior generated evidence')


if __name__ == '__main__':
    unittest.main()
