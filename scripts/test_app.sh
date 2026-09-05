#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/logs
result_bundle="build/logs/Lifecycle-$(uuidgen).xcresult"
xcodebuild -project NoteHush.xcodeproj -scheme NoteHush -configuration Debug \
  -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath build/UITestDerivedData \
  -resultBundlePath "$result_bundle" -parallel-testing-enabled NO \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 30 \
  -maximum-test-execution-time-allowance 60 \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual test 2>&1 | tee build/logs/app-tests.log
# The test app is signed for local execution. Verify the actual binary remains sandboxed.
codesign -d --entitlements :- build/UITestDerivedData/Build/Products/Debug/NoteHush.app \
  > build/logs/test-app-entitlements.plist 2> build/logs/test-app-signature.log
python3 -c 'import plistlib; p=plistlib.load(open("build/logs/test-app-entitlements.plist", "rb")); assert p.get("com.apple.security.app-sandbox") is True'
