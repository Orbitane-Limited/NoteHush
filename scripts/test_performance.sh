#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/logs
derived="build/PerformanceDerivedData"
application="$derived/Build/Products/ReleasePerformance/NoteHush.app"
destination="platform=macOS,arch=$(uname -m)"
xcodebuild -project NoteHush.xcodeproj -scheme NoteHushPerformance -configuration ReleasePerformance \
  -destination "$destination" -derivedDataPath "$derived" CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual \
  -showBuildSettings -json > build/performance-build-settings.json
python3 scripts/verify_performance_build.py build/performance-build-settings.json
xcodebuild -project NoteHush.xcodeproj -scheme NoteHushPerformance -configuration ReleasePerformance \
  -destination "$destination" -derivedDataPath "$derived" CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual \
  build-for-testing 2>&1 | tee build/logs/performance-build.log
codesign --force --sign - --entitlements Config/NoteHush.entitlements "$application"
python3 scripts/verify_test_app.py "$application" --configuration ReleasePerformance
result="build/logs/Performance-$(uuidgen).xcresult"
# These opt-in tests perform 20 full launches per case. Their allowance does not
# change the functional CI suite's 30/60-second per-case limits.
xcodebuild -project NoteHush.xcodeproj -scheme NoteHushPerformance -configuration ReleasePerformance \
  -destination "$destination" -derivedDataPath "$derived" -resultBundlePath "$result" \
  -parallel-testing-enabled NO -test-timeouts-enabled YES \
  -default-test-execution-time-allowance 600 -maximum-test-execution-time-allowance 600 \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual test-without-building 2>&1 | tee build/logs/performance-tests.log
python3 scripts/verify_test_app.py "$application" --configuration ReleasePerformance
xcrun xcresulttool export metrics --path "$result" --output-path "${result%.xcresult}-metrics"
xcrun xcresulttool get test-results metrics --path "$result" > "${result%.xcresult}-raw.json"
python3 scripts/summarize_performance.py "${result%.xcresult}-raw.json" "${result%.xcresult}-summary.json"
