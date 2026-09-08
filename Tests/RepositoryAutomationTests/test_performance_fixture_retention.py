"""Run the real shell control flow with fake native tools and owned temporary data."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]

FAKE_NATIVE = r'''
import json
import os
from pathlib import Path
import sys

root = Path(os.environ['FIXTURE_TEST_ROOT'])
name = Path(sys.argv[0]).name
arguments = sys.argv[1:]
if name == 'PerformanceFixtureHarness':
    stage = arguments[0]
elif name == 'python3':
    stage = Path(arguments[0]).name
elif name == 'xcrun':
    stage = 'metrics-' + arguments[1]
else:
    stage = name
with (root / 'calls.jsonl').open('a') as stream:
    stream.write(json.dumps(stage) + '\n')
if stage == 'prepare' and (root / 'build/performance-fixtures.json').exists():
    raise SystemExit(73)
if stage == os.environ.get('FAIL_STAGE'):
    raise SystemExit(int(os.environ.get('FAIL_STATUS', '7')))
if name == 'swift' and '--show-bin-path' in arguments:
    print(root / 'fake-bin')
elif stage == 'prepare':
    (root / 'build/performance-fixtures.json').write_text('generated fixture manifest')
    (root / 'generated-recovery').write_bytes(b'original generated recovery evidence')
elif stage == 'cleanup':
    (root / 'build/performance-fixtures.json').unlink()
    (root / 'generated-recovery').unlink()
'''


class PerformanceFixtureRetentionTests(unittest.TestCase):
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
            path.write_text(f'#!{sys.executable}\n' + FAKE_NATIVE)
            path.chmod(0o700)
        manifest = root / 'build/performance-fixtures.json'
        evidence = root / 'generated-recovery'
        if existing:
            manifest.write_text('prior generated manifest')
            evidence.write_bytes(b'prior generated evidence')
        environment = dict(os.environ, PATH=f"{root / 'fake-bin'}:/usr/bin:/bin",
                           FIXTURE_TEST_ROOT=str(root), FAIL_STAGE=failure or '', FAIL_STATUS=str(status))
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
        for stage in ['performance_environment.py', 'xcodebuild', 'verify_test_app.py',
                      'verify', 'metrics-export', 'metrics-get', 'summarize_performance.py']:
            with self.subTest(stage=stage):
                self.assert_retained_failure('test_performance.sh', stage)

    def testProfileAndPostProfileVerificationFailuresRetainOriginalFixtures(self):
        for stage in ['performance_environment.py', 'profile', 'verify_test_app.py']:
            with self.subTest(stage=stage):
                self.assert_retained_failure('profile_performance.sh', stage)

    def testInterruptedExitStatusIsPreservedWithoutCleanup(self):
        for status in [130, 143]:
            with self.subTest(status=status):
                self.assert_retained_failure('test_performance.sh', 'xcodebuild', status)

    def testCompleteSuccessCleansExactlyOnceAfterLastVerification(self):
        for script, final_stage in [('test_performance.sh', 'summarize_performance.py'),
                                    ('profile_performance.sh', 'verify_test_app.py')]:
            result, calls, manifest, evidence = self.run_script(script)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(calls[-2:], [final_stage, 'cleanup'])
            self.assertEqual(calls.count('cleanup'), 1)
            self.assertFalse(manifest.exists())
            self.assertFalse(evidence.exists())

    def testFailedSuccessPathCleanupFailsAndRetainsEvidence(self):
        for script in ['test_performance.sh', 'profile_performance.sh']:
            result, calls, manifest, evidence = self.run_script(script, 'cleanup', 9)
            self.assertEqual(result.returncode, 9, result.stderr)
            self.assertEqual(calls.count('cleanup'), 1)
            self.assertTrue(manifest.is_file())
            self.assertEqual(evidence.read_bytes(), b'original generated recovery evidence')

    def testFailedAcquisitionCannotCleanPreviouslyOwnedEvidence(self):
        for script in ['test_performance.sh', 'profile_performance.sh']:
            result, calls, manifest, evidence = self.run_script(script, existing=True)
            self.assertEqual(result.returncode, 73, result.stderr)
            self.assertNotIn('cleanup', calls)
            self.assertEqual(manifest.read_text(), 'prior generated manifest')
            self.assertEqual(evidence.read_bytes(), b'prior generated evidence')


if __name__ == '__main__':
    unittest.main()
