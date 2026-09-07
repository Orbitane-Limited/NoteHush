# Selected-editor focus investigation

Issue [#41](https://github.com/Orbitane-Limited/NoteHush/issues/41), version 0.1.0 (1). Restore the saved viewport before making the selected editor first responder. This keeps native text editing and independent caret/scroll restoration while avoiding the expensive initial focus layout observed in the generated mixed-script workspace. The complete 20-sample application comparison and final CI are still required before acceptance.

## Evidence and bounded reproduction

The [initial full app baseline](2026-09-07-app-launch-baseline.md) records 5 MiB readiness p95 of 2,237.930 ms. Its verified app-only trace contains 422 main-thread samples, with 360 under `NSTextView` becoming first responder and 348 under bidirectional processing. These cumulative stacks overlap; they are not durations, and the attached trace misses earlier startup.

An initial optimized AppKit-test reproduction failed its key-window assertion. That unhosted window did not establish the active focus path, so its phase timings are not accepted as application evidence. Its first build also needed testability enabled for the existing internal AppKit tests. The failed result is retained as `build/logs/EditorPresentation-Initial.xcresult` and `/tmp/notehush-issue41-presentation-initial.log`; no assertion was removed to accept it.

The replacement diagnostic ran inside the established isolated performance app, with the normal optimized configuration and no debugger. Temporary static signpost intervals separated loading, construction, tab-bar work, attachment, focus, scrolling and status setup. Each variant ran the unchanged 20-tab/5 MiB ASCII and Arabic/combining-mark/emoji CRLF workload with five measured fresh processes plus XCTest warm-up. All six readiness, selected-tab/digest, keyboard edit, Undo and normal Cmd+Q cycles passed in each variant. Signature checks and fixture cleanup passed. These single-workload probes intentionally do not claim the full protocol's final all-workspace verification or 20-sample baseline.

[Every diagnostic sample and sanitized provenance](2026-09-07-editor-focus-diagnostics.json) is retained. Both variants use base `421f24ec6a9e53c375377205af2e8abb2d3ae4aa` with a correctly recorded dirty checkout. Before source executable hash: `91e03b1e146f94892bfe42ea5a73b83d106920ff85e032b3e6f103497344d8fb`; candidate: `1e97a14a2cf3f1369d45f74105624b9bcab9671e07074ccc789491762058340c`. Both ran on the same M4 Pro/24 GiB, macOS 26.6.2, Xcode 26.6, AC power and warm filesystem caches after main CI completed. Initial thermal state differed: **fair (1)** before, **nominal (0)** for the candidate. Other human/application input exclusivity was not independently verified. This short probe identifies the changed layout path; it is not a controlled reference-hardware speedup claim.

Median milliseconds from five observations per interval:

| Interval | Focus before scroll | Scroll before focus |
| --- | ---: | ---: |
| RecoveryLoad | 44.661 | 35.412 |
| EditorConstruction | 277.033 | 216.753 |
| WorkspaceChrome | 37.118 | 28.426 |
| EditorAttachment | 39.927 | 31.453 |
| EditorFocus | 1772.771 | 1.436 |
| EditorScroll | 0.200 | 324.307 |
| EditorStatus | 0.637 | 0.575 |
| ProcessToEditorReady | 2376.750 | 789.673 |

The ordering change moves the substantive viewport preparation into native scroll restoration before focus. These are individual interval medians; do not add them or treat the overall readiness interval as complete LaunchServices-to-screen latency. No p95 or product-budget acceptance is derived from these five-sample diagnostics.

Raw results: `PhaseDiagnosis-305BF5AD-67A2-4896-92B8-B43F4BCCE33F.xcresult` and `PhaseDiagnosis-7B81EA90-BCE2-41F9-BA2B-D3EFC245BF2C.xcresult`, adjacent raw/environment JSON under `build/logs`. Logs and exact temporary source diffs are `/tmp/notehush-issue41-application-phases.log`, `/tmp/notehush-issue41-scroll-before-focus.log`, `/tmp/notehush-issue41-application-phases.diff` and `/tmp/notehush-issue41-scroll-before-focus-diagnostic.diff`. The extra intervals and five-iteration override were removed before the final candidate; the standard suite again requires all three workloads and 20 observations per original metric.

## Correctness and implementation

The product change only reorders `restoreScroll()` and `makeFirstResponder`. It retains native anchor scrolling, noncontiguous layout, text bytes, natural writing direction, per-tab undo, recovery storage and all four sandbox entitlements. Apple's [NSTextView documentation](https://developer.apple.com/documentation/appkit/nstextview) describes insertion-point/selection updates when becoming first responder and requires callers to use the window's `makeFirstResponder` API, as this change does.

`ColdLaunchHarness` adds four active-app launches covering a 256 KiB mixed-script draft with its caret at the start while viewing the middle, then its caret near the end while viewing the top. Each case restarts again from the app's checkpoint. The oracle checks exact text and selection, the independently specified zero-based logical line (8,001 or 0) and saved offset within one point, plus retained history/preferences/file metadata and unchanged external fixture bytes. Counting uses LF UTF-16 units because Swift treats a CRLF pair as one Character. A line's leftmost glyph need not be its first logical character, so the viewport oracle compares logical line and offset. Normal termination and exact returned bundle URL/identifier are required; existing ten-second observation bounds remain unchanged.

The finalized cold-launch harness passed, including all its preceding isolation/file/dirty-recovery scenarios. The candidate's exact sandbox signature and DebugUITesting build passed. All **33 AppKit tests passed in 16.579 seconds**, including the existing deep-scroll one-point checks, hidden large editors, marked text, Unicode, undo, preferences, printing and failure handling. Retained logs: `/tmp/notehush-issue41-cold-scroll-final.log`, `/tmp/notehush-issue41-appkit.log`, and `build/logs/EditorFocus-AppKit.xcresult`.

## Remaining validation

Run the unchanged full optimized launch protocol from a clean source, retain all 120 observations and final buffer verification, and record the candidate's separate app-only profile. Full final-head CI remains required. M1/8 GB, minimum macOS/Intel, event-to-visible typing, switching, memory/idle energy, large-file/display/printing/history budgets, accessibility, signing and TestFlight remain separate gates. No release or speed marketing claim follows from this diagnostic.
