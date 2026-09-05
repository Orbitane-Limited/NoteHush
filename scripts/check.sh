#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/logs
xcodebuild -version | tee build/logs/toolchain.log
swift --version | tee -a build/logs/toolchain.log
python3 scripts/verify_configuration.py
xcrun swift-format lint --strict --recursive App Sources Tests Package.swift
swift test --enable-code-coverage 2>&1 | tee build/logs/core-tests.log
xcodebuild -project NoteHush.xcodeproj -scheme NoteHush -configuration Debug \
  -destination 'generic/platform=macOS' -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO build 2>&1 | tee build/logs/debug-build.log
bash scripts/archive.sh
