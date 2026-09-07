# Selected-editor focus investigation

Issue [#41](https://github.com/Orbitane-Limited/NoteHush/issues/41), version 0.1.0 (1). Restore the saved viewport before making the selected editor first responder. This keeps native text editing and independent caret/scroll restoration while avoiding the expensive initial focus layout observed in the generated mixed-script workspace. The complete 20-sample comparison, exact recovery checks and app-only profiling passed. Final-head CI remains the merge gate; minimum-hardware and other product budgets remain open.

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

## Complete unprofiled comparison

`bash scripts/test_performance.sh` passed on clean source `63d4f30b9695ea7dbda3fa685b1b0d4fe8d94cc1`, executable SHA-256 `87ae7acd1ab60c0156b43a4ad012fe025c1ea9a26daf0fd9802f49a646910e6a`. The extra diagnostic hooks and five-iteration override were removed. The product app source remains unchanged after that measurement; a subsequent host-test change makes process ownership contingent on exact bundle verification before failure cleanup.

Provenance was captured at 03:52:09 UTC. The baseline and candidate both used the M4 Pro/24 GiB, macOS 26.6.2 (25G83), Xcode 26.6 (17F113), Swift 6.3.3, AC power, low-power mode off, fair initial thermal state (1), one 3440 × 1440-point display at scale 1 and warm filesystem caches. NoteHush CI and other local GUI automation were complete before each measurement; other human/application input exclusivity was not independently verified. These are initial conditions, not continuous thermal monitoring or an M1/8 GB certification.

All **63** fresh-process launch/readiness/selected-tab/text/edit/Undo/Cmd+Q cycles passed. XCTest excluded its single warm-up per workload; all **120** exported observations were retained, with exactly 20 finite nonnegative seconds samples for each original interval in every scenario, no retries or trimming. Exact final open/closed text digests, tab order, selected tab and advanced recovery revisions passed host verification. Build settings, exact sandbox signatures, CSV/raw JSON export and fixture cleanup passed.

Entry-to-editor-ready milliseconds:

| Workspace | Before median | Before p95 | Candidate median | Candidate p95 |
| --- | ---: | ---: | ---: | ---: |
| Empty | 198.042 | 267.138 | 180.038 | 219.695 |
| 20 tabs / 5 MiB | 1904.724 | 2237.930 | 789.285 | 852.798 |
| 100 open + 20 closed / 30 MiB | 3016.358 | 3087.787 | 1899.178 | 1951.239 |

Candidate Apple first-frame launch milliseconds, reported separately:

| Workspace | Median | p95 |
| --- | ---: | ---: |
| Empty | 275.130 | 302.011 |
| 20 tabs / 5 MiB | 283.430 | 305.455 |
| 100 open + 20 closed / 30 MiB | 266.054 | 288.870 |

The 5 MiB readiness p95 is now **852.798 ms** on this Mac, below the one-second restoration target on this hardware. The reference M1/8 GB is still unverified, and the interval excludes pre-entry loader/LaunchServices work. This does not establish post-reboot cold launch, event-to-visible typing or other #12 budgets. Apple first-frame and readiness intervals overlap and must not be added.

[All candidate observations](2026-09-07-app-launch-after-focus-metrics.json) and [sanitized provenance](2026-09-07-app-launch-after-focus-environment.json) are committed alongside the original baseline. Raw evidence is `build/logs/Performance-A660D93A-5757-4D49-BA3B-3AD28ACFC568.xcresult`, adjacent CSV/raw/summary/environment exports and `/tmp/notehush-issue41-full-performance.log`. Case durations were 82.968, 90.706 and 100.130 seconds respectively; these are whole-test durations, not launch samples. The log retains 26 event-loop-monitor diagnostics, all during Tear Down after metrics: 8 empty, 11 at 5 MiB, 7 at 30 MiB. Their cause remains unverified; all samples and functional checks passed and none were suppressed.

## Separate candidate profile

`bash scripts/profile_performance.sh` passed on the same clean source and executable hash, with provenance captured at 03:58:25 UTC. Recorder success, exact PID ownership, normal termination, complete recovered-buffer verification, TOC export, sandbox signature and cleanup passed. `PerformanceAttached-F9DA3788-0275-46DB-B024-DE25A5043B16.trace` and its exported Time Profiler table contain **two samples, both from the verified fixture app**, one on the main thread, over about 10.75 seconds. This attached recording starts after LaunchServices/attachment overhead and does not establish a startup breakdown or 60-second idle-CPU acceptance. The unprofiled comparison above provides the launch/readiness measurements.

Retained evidence: the trace, adjacent TOC/sample XML and profile-environment JSON under `build/logs`, plus `/tmp/notehush-issue41-profile.log`. Raw traces/TOCs can contain device and process-environment metadata; only the whitelisted measurement provenance and sample summaries are committed.

## Remaining gates

Full final-head CI remains required. M1/8 GB, minimum macOS/Intel, event-to-visible typing, switching, memory/idle energy, large-file/display/printing/history budgets, accessibility, signing and TestFlight remain separate gates. No release or speed marketing claim follows from this Mac's measurements alone.
