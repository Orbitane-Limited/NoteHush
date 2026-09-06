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
result_bundle="build/logs/Lifecycle-$(uuidgen).xcresult"
xcodebuild -project NoteHush.xcodeproj -scheme NoteHush -configuration Debug \
  -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath build/UITestDerivedData \
  -resultBundlePath "$result_bundle" -parallel-testing-enabled NO \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 30 \
  -maximum-test-execution-time-allowance 60 \
  -skip-testing:NoteHushUITests/FileAccessTests/testUnavailableVolumeRestoresDraftWithoutMounting \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual test 2>&1 | tee build/logs/app-tests.log
python3 scripts/volume_fixture.py detach
offline_result="build/logs/OfflineVolume-$(uuidgen).xcresult"
xcodebuild -project NoteHush.xcodeproj -scheme NoteHush -configuration Debug \
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
# The test app is signed for local execution. Verify the actual binary remains sandboxed.
codesign -d --entitlements :- build/UITestDerivedData/Build/Products/Debug/NoteHush.app \
  > build/logs/test-app-entitlements.plist 2> build/logs/test-app-signature.log
python3 -c 'import plistlib; p=plistlib.load(open("build/logs/test-app-entitlements.plist", "rb")); assert all(p.get(k) is True for k in ("com.apple.security.app-sandbox", "com.apple.security.files.user-selected.read-write", "com.apple.security.files.bookmarks.app-scope"))'
