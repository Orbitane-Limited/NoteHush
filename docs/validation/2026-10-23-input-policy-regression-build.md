# Literal input policy regression build

This is additional compile-time evidence for #64 and PR #65. The existing test that covers marked-text composition now also asserts the per-view generated-text opt-outs and that the user's explicit spell-checking preference remains enabled. No product behavior changed in this update.

## Validation

Environment: arm64, macOS 26.6.2, Xcode 26.6 (17F113), Swift 6.3.3.

| Check | Command / scope | Result |
| --- | --- | --- |
| App and test-bundle compilation | `xcodebuild build-for-testing -project NoteHush.xcodeproj -scheme NoteHush -destination 'platform=macOS,arch=arm64' -derivedDataPath build/issue-64-derived CODE_SIGNING_ALLOWED=NO` | Passed; `TEST BUILD SUCCEEDED` |
| Core tests | `swift test --enable-code-coverage` | 85 passed, 0 failures |
| Repository automation tests | `python3 -m unittest discover -s Tests/RepositoryAutomationTests -v` | 45 passed, 0 failures |
| Configuration | `python3 scripts/verify_configuration.py` | Passed; version 0.1.0 (1) |
| Swift formatting | `xcrun swift-format lint --strict Tests/NoteHushAppTests/PreferencesTests.swift App/NoteHush/Editor/EditorTab.swift` | Passed |
| Focused AppKit regression | `xcodebuild test -only-testing:NoteHushAppTests/PreferencesTests/testDisplayChangesKeepMarkedTextAndDisableAutomaticSubstitutions` | Passed; 1 test, 0 failures. It uses programmatic marked text and opens no window |
| Remaining AppKit and UI tests | Not run | The exclusive desktop-input window has expired |
| Full CI | Not rerun | A push would start the native UI suite on the self-hosted Mac; current PR checks also cannot publish artifacts while the organization quota is exhausted |

The focused AppKit result validates the new opt-out assertions together with marked-text composition and optional spelling. The successful `build-for-testing` action also compiles all test bundles. Final-head CI, the remaining native tests, human review and runtime checks remain required before PR #65 can merge.
