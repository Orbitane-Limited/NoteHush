# Paragraph direction regression recheck

Issue #45, source head `8bc1692efcd73e1d26cddb4839bea3599dcd5c0d`. The implementation is unchanged; this records a fresh local regression run because the hosted PR check remains canceled.

Environment: arm64, macOS 26.6.2 (25G83), Xcode 26.6 (17F113), Swift 6.3.3.

| Check | Command / scope | Result |
| --- | --- | --- |
| Core suite | `env SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/NoteHushSwiftModuleCache swift test --enable-code-coverage --scratch-path build/issue45-core-derived --manifest-cache local --disable-sandbox` | Passed; 85 tests, 0 failures. The suite uses generated temporary file fixtures. |
| Crash recovery | `scripts/test_crash_recovery.py` and `scripts/test_crash_recovery.py --configuration release` | Passed; 83 Debug and 83 Release process-kill/publication-phase drills. All use disposable generated workspaces. |
| Focused AppKit regression | `xcodebuild test -project NoteHush.xcodeproj -scheme NoteHush -destination 'platform=macOS,arch=arm64' -derivedDataPath build/issue45-derived -only-testing:NoteHushAppTests/ParagraphDirectionTests CODE_SIGNING_ALLOWED=NO` | Passed; 3 tests, 0 failures. Generated attributed text only; no window or user documents. |
| Swift formatting | `xcrun swift-format lint --strict --recursive App Sources Tests Package.swift` | Passed |
| Configuration | `python3 scripts/verify_configuration.py` | Passed; version 0.1.0 (1) |
| Whitespace | `git diff --check` | Passed |

An initial package test under the workspace's restricted process sandbox could not exercise generated security-scoped file fixtures; 14 file-coordination assertions failed to open those temporary fixtures. The identical 85-test suite passed in the host test context with no assertion or timeout changes. The focused cases cover native statistical direction agreement for generated Unicode and paragraph separators, preservation of source text and attributes, explicit-direction behavior, and native fallback for empty or oversized paragraphs. They do not replace the full AppKit suite, native UI automation, final-head hosted CI, review, or release acceptance. No user data was opened.
