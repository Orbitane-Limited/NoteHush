#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/logs
if ! mkdir build/volume-fixture.lock; then
  echo 'Another fixture run or an interrupted setup needs inspection before rerunning.' >&2
  exit 1
fi
if [[ -e build/volume-fixture.json ]]; then
  rmdir build/volume-fixture.lock
  echo 'An existing fixture needs cleanup before rerunning.' >&2
  exit 1
fi
trap 'python3 scripts/volume_fixture.py cleanup' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
python3 scripts/volume_fixture.py create
test_app="build/UITestDerivedData/Build/Products/DebugUITesting/NoteHush.app"
xcodebuild -project NoteHush.xcodeproj -scheme NoteHush -configuration DebugUITesting \
  -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath build/UITestDerivedData \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual build-for-testing 2>&1 | tee build/logs/app-build.log
# Xcode adds filesystem exceptions when building for tests. The app under test
# must use the shipping entitlement scope; the XCTest runner is a separate process.
codesign --force --sign - --entitlements Config/NoteHush.entitlements "$test_app"
python3 scripts/verify_test_app.py "$test_app"
swift run ColdLaunchHarness "$test_app" 2>&1 | tee build/logs/cold-launch-tests.log
result_bundle="build/logs/Lifecycle-$(uuidgen).xcresult"
xcodebuild -project NoteHush.xcodeproj -scheme NoteHush -configuration DebugUITesting \
  -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath build/UITestDerivedData \
  -resultBundlePath "$result_bundle" -parallel-testing-enabled NO \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 30 \
  -maximum-test-execution-time-allowance 60 \
  -skip-testing:NoteHushUITests/FileAccessTests/testUnavailableVolumeRestoresDraftWithoutMounting \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual test-without-building 2>&1 | tee build/logs/app-tests.log
python3 scripts/verify_test_app.py "$test_app"
python3 scripts/volume_fixture.py detach
offline_result="build/logs/OfflineVolume-$(uuidgen).xcresult"
xcodebuild -project NoteHush.xcodeproj -scheme NoteHush -configuration DebugUITesting \
  -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath build/UITestDerivedData \
  -resultBundlePath "$offline_result" -parallel-testing-enabled NO \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 30 \
  -maximum-test-execution-time-allowance 60 \
  -only-testing:NoteHushUITests/FileAccessTests/testUnavailableVolumeRestoresDraftWithoutMounting \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual test-without-building 2>&1 | tee -a build/logs/app-tests.log
python3 - <<'PY'
from pathlib import Path
import re
log = Path('build/logs/app-tests.log').read_text()
for name in ('testMountedVolumeSaveAndQuitKeepsUnsavedDraft',
             'testUnavailableVolumeRestoresDraftWithoutMounting'):
    if not re.search(r"Test Case '-\[[^\]]+ " + name + r"\]' passed", log):
        raise SystemExit(f'Required volume scenario did not pass: {name}')
PY
python3 scripts/verify_test_app.py "$test_app"
