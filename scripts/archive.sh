#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/check_runner_storage.py
mkdir -p build/logs
xcodebuild -project NoteHush.xcodeproj -scheme NoteHush -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath build/ReleaseDerivedData \
  -archivePath build/NoteHush-unsigned.xcarchive \
  CODE_SIGNING_ALLOWED=NO archive 2>&1 | tee build/logs/release-archive.log
lipo build/NoteHush-unsigned.xcarchive/Products/Applications/NoteHush.app/Contents/MacOS/NoteHush \
  -verify_arch arm64 x86_64
python3 scripts/verify_configuration.py build/NoteHush-unsigned.xcarchive
