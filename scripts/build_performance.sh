#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/logs
derived="build/PerformanceDerivedData"
application="$derived/Build/Products/ReleasePerformance/NoteHush.app"
destination="platform=macOS,arch=$(uname -m)"
xcodebuild -project NoteHush.xcodeproj -scheme NoteHushPerformance -configuration ReleasePerformance \
  -destination "$destination" -derivedDataPath "$derived" CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual \
  -showBuildSettings -json > build/logs/performance-build-settings.json
python3 scripts/verify_performance_build.py build/logs/performance-build-settings.json
xcodebuild -project NoteHush.xcodeproj -scheme NoteHushPerformance -configuration ReleasePerformance \
  -destination "$destination" -derivedDataPath "$derived" CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual \
  build-for-testing 2>&1 | tee build/logs/performance-build.log
codesign --force --sign - --entitlements Config/NoteHush.entitlements "$application"
python3 scripts/verify_test_app.py "$application" --configuration ReleasePerformance
