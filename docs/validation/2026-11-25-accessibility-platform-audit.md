# Accessibility, Unicode and platform audit

Issue #13 audit started 2026-11-25. This is a coverage inventory, not a completed platform validation. No acceptance criterion is marked passed from source inspection alone.

## Existing automated coverage

The repository already contains focused tests for these behaviors:

| Area | Existing automated coverage | What it establishes |
| --- | --- | --- |
| Unicode direction and mixed paragraphs | `Tests/NoteHushAppTests/ParagraphDirectionTests.swift` | Compares natural writing-direction projection with Unicode direction data for Urdu, Hebrew, mixed-direction text, emoji and combining marks across line separators. It is a macOS 26 API test and does not exercise a real keyboard input source. |
| Marked text and Japanese composition model | `EditorSnapshotTests.testMarkedTextCommitAndUndoAreCapturedExactly` and `PreferencesTests.testDisplayChangesKeepMarkedTextAndDisableAutomaticSubstitutions` | Sends synthetic AppKit marked-text and commit calls, checks exact text capture, selection/undo behavior, and preservation when display preferences change. It does not verify Japanese or Chinese IME candidate UI or hardware keyboard input. |
| Per-tab undo | `WorkspaceIntegrationTests.testEditorUndoHistoryDoesNotCrossTabs` and `TabManagementTests.testReorderKeepsSelectedEditorUndoAndRestoresOrder` | Verifies undo histories remain attached to their tabs when switching or reordering. |
| Accessibility semantics and keyboard tab navigation | `TabManagementTests.testTabAccessibilitySemanticsWithoutWindow` and `TabManagementUITests.testOverflowMenuAndKeyboardNavigationRevealHiddenTabs` | Checks tab accessibility metadata and keyboard navigation for hidden tabs. It does not replace a VoiceOver pass or full-app keyboard-only workflow. |
| Mixed-script and grapheme preservation | `EditorSnapshotTests`, `TextMetricsTests`, and `TextFileServiceTests` | Covers generated Urdu/Arabic text, emoji, combining sequences, UTF-16 selections and supported file byte round trips. This is programmatic coverage, not visual glyph-shaping review. |
| Appearance and settings | `PreferencesUITests.testSettingsFontAppearanceWrapSpellingZoomAndQuitPersistence` and `testZoomShortcutsAndAppearanceUpdatesKeepText` | Exercises the app's System/Light/Dark appearance settings and text preservation through UI automation. It does not assess contrast or reduced-motion behavior with macOS accessibility settings. |
| Window frame / display removal | `WorkspaceIntegrationTests.testRestoresScrollSelectionAndClampsDisconnectedDisplayFrame` and `WorkspaceLifecycleTests.testRedWindowCloseRestoresLatestDraftAndWindowFrame` | Tests persisted geometry and clamping when a saved display frame is unavailable. It does not test a physical multi-display setup or interactive resizing across displays. |

The exact issue-branch head `ba9a85d0f55258cc9af2cbe9a731eaa8c9b6abd3` passed the complete hosted `bash scripts/check.sh` workflow in [CI run 45518783711](https://github.com/Orbitane-Limited/NoteHush/actions/runs/45518783711), using `macos-26` and Xcode 26.6. This validates the automated suites included by that workflow on its hosted runner; it does not establish manual accessibility, real IME, macOS 14, Intel, or physical multi-display coverage.

## Observed environment and outstanding validation

The available local Mac reports macOS 26.6.2 and `arm64`. The read-only UI automation preflight reported that Automation Mode is disabled and requires administrator authentication. Therefore no local native UI or accessibility session was started. The available evidence does not establish this Mac's physical model or memory size.

| Acceptance area | Status | Required evidence before claiming coverage |
| --- | --- | --- |
| VoiceOver, full keyboard access, contrast, reduced motion | **Untested / release blocker** | Manual run on the built app, including navigation and editing without a pointer, VoiceOver labels/focus order, increased contrast, and reduced-motion system setting. Save sanitized observations and screenshots without user data. |
| Urdu/RTL, emoji and combining marks | **Automated logic/model coverage exists; visual and physical-input checks untested** | Type and inspect representative text using the actual input sources; verify caret movement, selection, shaping, line wrapping, save/reopen and undo. |
| Japanese and Chinese IMEs | **Synthetic marked-text coverage only; real IME checks untested** | Use installed Japanese and Chinese input sources and exercise candidate selection, composition cancellation/commit, undo and tab switching in the running app. |
| Per-tab undo | **Automated coverage exists; hosted exact-head run pending** | Confirm CI result for the named AppKit/UI tests; manual keyboard workflow can supplement it. |
| macOS 14 | **Untested** | Launch and exercise the app on macOS 14. An SDK build or deployment-target setting is not runtime evidence. |
| Current stable macOS | **Partial environment evidence only** | Record exact CI/local macOS and test results; hosted macOS 26 is a virtual runner and does not replace physical Mac validation. |
| Apple silicon and Intel | **Intel runtime untested** | Run the app and relevant UI scenarios on physical Apple silicon and Intel Macs. Universal binary inspection alone is insufficient. |
| Multiple displays, resizing and dark mode | **Automated frame/appearance checks exist; physical interaction untested** | Move and resize windows across connected displays; repeat appearance changes while editing and verify restored geometry. |
| Fresh install and upgrade | **Untested for this matrix** | Exercise a clean install and upgrade from the immediately preceding build with isolated, generated content; confirm recovery, preferences and file access. |

All untested combinations above remain release blockers for the supported-platform/accessibility claim in #13. Do not infer App Store readiness or close #13 from the automated tests alone.

## Repeatable check

Run the repository's required native validation on the exact issue head:

```sh
bash scripts/check.sh
```

Record commit, workflow URL, runner OS/architecture, tests actually executed, and skipped tests. The native UI suite requires an authorized awake GUI session and exclusive input. No UI automation authorization is changed by this audit.
