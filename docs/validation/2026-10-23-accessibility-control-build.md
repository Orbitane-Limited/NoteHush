# Workspace accessibility regression build

Issue #13 remains open. This change strengthens automated checks for accessible
workspace controls; it does not replace VoiceOver, full-keyboard, contrast,
reduced-motion, IME, or supported-platform validation.

## Change

The 100-tab AppKit regression now checks the New Tab and All Tabs labels, tab
radio-button roles, exactly one selected tab, positional and dirty-state labels,
and the active tab's close-button label.

## Validation

- `xcrun swift-format lint --strict --recursive App Sources Tests Package.swift` — passed.
- `python3 scripts/verify_configuration.py` — passed; NoteHush 0.1.0 configuration is valid.
- `git diff --check` — passed.
- `swift test --enable-code-coverage` — 85 Foundation-only core tests passed with no failures.
- `xcodebuild -project NoteHush.xcodeproj -scheme NoteHush -configuration Debug -destination 'generic/platform=macOS' -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build-for-testing` — passed; app, AppKit tests, UI tests, and both arm64/x86_64 slices compiled. Tests were not launched.

The build reports the existing `NSBox.borderType` deprecation in
`TabBarView.swift`, tracked separately by issue #54. No runtime accessibility
behavior, VoiceOver output, GUI interaction, or physical Intel/minimum-OS
behavior was observed in this build-only check.
