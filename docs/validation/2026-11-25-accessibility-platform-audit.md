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

Before the architecture matrix was added, exact issue-branch head `ba9a85d0f55258cc9af2cbe9a731eaa8c9b6abd3` passed the complete hosted `bash scripts/check.sh` workflow in [CI run 45518783711](https://github.com/Orbitane-Limited/NoteHush/actions/runs/45518783711), using `macos-26` and Xcode 26.6. This validates the automated suites included by that workflow on its Apple-silicon hosted runner; it does not establish manual accessibility, real IME, macOS 14, Intel, or physical multi-display coverage.

The architecture-matrix run on exact head `72a8c74a44e0f473b223be7e412fd97ac5c65214` completed on 2026-11-25 as [CI run 45522890066](https://github.com/Orbitane-Limited/NoteHush/actions/runs/45522890066). The Apple-silicon `macos-26` job passed the full workflow in 15m11s. The Intel `macos-26-intel` job failed after 30m26s: the non-UI/AppKit tests and cold-launch recovery harness passed, but the first XCUITest did not observe the expected empty status value (`EditingTests.swift:99`), and subsequent UI cases repeatedly exceeded their 60-second test allowance. This is an unresolved hosted-Intel UI validation failure, not evidence of Intel compatibility. The full logs are retained in GitHub artifact `14982701603` for seven days. The log shows the same Xcode debugger-version diagnostic on the passing Apple-silicon job, so that diagnostic alone does not explain the Intel-specific failures.

An explicit static-text role was added to the three status labels and tested on exact head `6b0b86b85aa7afe9fb99d9936c42b3403c6e6d06` in [CI run 45529321807](https://github.com/Orbitane-Limited/NoteHush/actions/runs/45529321807). The Apple-silicon job passed in 15m18s. The Intel job reached the same failure: `EditingTests.testEmptyAndNoMatchSearchDoNotChangeText` still could not observe `status-counts`, then many unrelated UI cases stalled during accessibility queries or synthetic input and exceeded their 60-second allowance. The job was cancelled by its 30-minute limit. Its retained log artifact is `14985900423`; the `.xcresult` is incomplete because Xcode was interrupted. The explicit role alone did not fix the query.

The first explicit-child-group implementation was tested on exact head `b48f6ba1d066fd501aa96667190c635b22504f34` in [CI run 45537245574](https://github.com/Orbitane-Limited/NoteHush/actions/runs/45537245574). Apple silicon passed in 17m05s, including the status UI scenario. Intel again failed to observe `status-counts` and was cancelled at the 30-minute job limit after unrelated UI cases stalled on accessibility queries and synthesized input. Its log artifact is `14988798059`. In that implementation, `setAccessibilityChildren` ran before the arranged row was added and the label traits were configured.

Moving the explicit hierarchy assignment to the end of view construction was tested on exact head `39245cdaeb5e0bef45ac2f8e708b377b2fb784df` in [CI run 45542050333](https://github.com/Orbitane-Limited/NoteHush/actions/runs/45542050333). Apple silicon passed in 14m39s, including the full UI suite. Intel still failed to observe `status-counts` and was cancelled at the 30-minute job limit; unrelated UI cases again stalled on accessibility queries and synthesized input. Its log artifact is `14991526720`. This rules out the ordering change as sufficient. The next candidate makes the accessible group a plain `NSView` containing the layout stack, so the custom child hierarchy does not rely on `NSStackView`'s accessibility implementation. That change is not yet verified.

The plain-`NSView` candidate now keeps the existing layout in an internal vertical `NSStackView`, pinned to the container edges, while exposing the three static-text labels as explicit accessibility children. Local `xcodebuild` Debug build, strict `swift-format` lint and `git diff --check` pass. The hosted Apple-silicon and Intel UI matrix has not yet tested this candidate.

## Observed environment and outstanding validation

The available local Mac reports macOS 26.6.2 and `arm64`. The read-only UI automation preflight reported that Automation Mode is disabled and requires administrator authentication. Therefore no local native UI or accessibility session was started. The available evidence does not establish this Mac's physical model or memory size.

| Acceptance area | Status | Required evidence before claiming coverage |
| --- | --- | --- |
| VoiceOver, full keyboard access, contrast, reduced motion | **Untested / release blocker** | Manual run on the built app, including navigation and editing without a pointer, VoiceOver labels/focus order, increased contrast, and reduced-motion system setting. Save sanitized observations and screenshots without user data. |
| Urdu/RTL, emoji and combining marks | **Automated logic/model coverage exists; visual and physical-input checks untested** | Type and inspect representative text using the actual input sources; verify caret movement, selection, shaping, line wrapping, save/reopen and undo. |
| Japanese and Chinese IMEs | **Synthetic marked-text coverage only; real IME checks untested** | Use installed Japanese and Chinese input sources and exercise candidate selection, composition cancellation/commit, undo and tab switching in the running app. |
| Per-tab undo | **Apple-silicon automated coverage passed; Intel UI case unverified** | The named AppKit/UI tests passed on the Apple-silicon leg. Intel AppKit tests passed, but the UI run timed out before the per-tab undo UI case completed. |
| macOS 14 | **Untested / release blocker** | GitHub's hosted macOS 14 image became unsupported on 2026-11-02; use a compatible physical Mac or approved VM to launch and exercise the app. An SDK build or deployment-target setting is not runtime evidence. See [the current hosted runner matrix](https://docs.github.com/en/actions/reference/runners/github-hosted-runners) and [runner image deprecation notice](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-Readme.md). |
| Current stable macOS | **Apple-silicon hosted run passed; Intel UI validation failed** | The exact-head `macos-26` job passed; the `macos-26-intel` job timed out after UI test failures. A hosted VM does not replace physical Mac validation. |
| Apple silicon and Intel | **Apple-silicon hosted full suite passed; Intel cold-launch passed but UI suite failed** | The Intel run passed the non-UI/AppKit tests and native cold-launch recovery harness, but its XCUITest suite failed and timed out. Physical Intel and Apple-silicon validation remain separate evidence; a universal binary alone is insufficient. |
| Multiple displays, resizing and dark mode | **Automated frame/appearance checks exist; physical interaction untested** | Move and resize windows across connected displays; repeat appearance changes while editing and verify restored geometry. |
| Fresh install and upgrade | **Untested for this matrix** | Exercise a clean install and upgrade from the immediately preceding build with isolated, generated content; confirm recovery, preferences and file access. |

All untested combinations above remain release blockers for the supported-platform/accessibility claim in #13. Do not infer App Store readiness or close #13 from the automated tests alone.

## Repeatable check

Run the repository's required native validation on the exact issue head:

```sh
bash scripts/check.sh
```

Record commit, workflow URL, runner OS/architecture, tests actually executed, and skipped tests. The native UI suite requires an authorized awake GUI session and exclusive input. No UI automation authorization is changed by this audit.
