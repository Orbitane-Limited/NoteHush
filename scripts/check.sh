#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/logs
xcodebuild -version | tee build/logs/toolchain.log
if [[ "$(head -n 1 build/logs/toolchain.log)" != "Xcode 26.6" ]]; then
  echo 'Expected Xcode 26.6. Review a toolchain upgrade before changing this check.' >&2
  exit 1
fi
swift --version | tee -a build/logs/toolchain.log
python3 scripts/verify_configuration.py
xcrun swift-format lint --strict --recursive App Sources Tests Package.swift
swift test --enable-code-coverage 2>&1 | tee build/logs/core-tests.log
python3 scripts/test_crash_recovery.py 2>&1 | tee build/logs/crash-tests.log
python3 scripts/test_crash_recovery.py --configuration release 2>&1 | tee -a build/logs/crash-tests.log
bash scripts/test_app.sh
xcodebuild -project NoteHush.xcodeproj -scheme NoteHush -configuration Debug \
  -destination 'generic/platform=macOS' -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO build 2>&1 | tee build/logs/debug-build.log
bash scripts/archive.sh
