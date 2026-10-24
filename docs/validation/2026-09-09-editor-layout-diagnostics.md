# Editor layout experiments and failed integration

Date: 2026-09-09 PKT, starting 2026-09-08 22:25 UTC. Issue #45; main baseline `bb49b49c5cb3ead161f774d087d9fd26481f73e1`. These are separate diagnostic experiments. They do not establish a production speedup, a release-budget pass, an accepted editor migration or complete CI.

## Isolation and unchanged limits

The user confirmed exclusive Mac availability for eight hours from 22:04:56 UTC. CI finished before these cases; the runner's repository label was held because macOS reported Automation Mode disabled with administrator authentication required. No competing agent-started native job, compiler or profiler ran during the diagnostic app cases. The machine was the M4 Pro/24 GiB, macOS 26.6.2 (25G83), Xcode 26.6 (17F113), Swift 6.3.3. The selected installed SDK was macOS 26.5. Caches were warm; these were fresh processes. Thermal conditions were not continuously monitored, and M1/8 GiB remains unverified.

Each private app required its distinct diagnostic bundle identifier and a fresh UUID, used the exact four product sandbox entitlements, and stored evidence only in its generated container workspace. The host verified the returned bundle URL/identifier and owned process. Input was one new app-local `NSEvent` through `NSApp.sendEvent`, with exact text, UTF-16 selection and Undo checks. It did not use global keyboard events, AX, the clipboard or another app's UI. No system authorization interface was inspected or changed.

Every functional case retained 20 planned observations, a 100 ms gap between observations, a 20-second host limit and a 30-second outer bound. The geometry-only case intentionally performed zero edits and claimed no functional/timing pass. Failed variants, all partial evidence, source/build logs and binaries remain private; no unchanged case was retried until green. The [complete numeric observations and source/binary provenance](2026-09-09-editor-layout-diagnostics.json) retain successful and failed experiments separately. The standalone host's success message predates the viewport check; the records and assertions establish which checks actually ran.

## Legacy layout-range observation

A production-derived `EditorTab` changed only the layout-manager constructor to a forwarding observer. It recorded public invalidation/layout calls and numeric glyph batches during dispatch, without changing their parameters or suppressing native work. Its 1 MiB ASCII case completed 20 observations. The mixed-script case reached only 15 of 20 before the fixed host limit, so it is an incomplete failure and supplies no accepted performance comparison.

The last completed mixed observation edited one UTF-16 unit at 360574 and invalidated 12 units. Its 39.379 ms dispatch included a 38.898 ms `processEditing`, a 30.013 ms viewport-bounds layout call and 29.881 ms ensuring a 331-glyph range. Ten generated batches contained 24 glyphs spanning character indices 360574–360585. The recorder did not truncate this observation.

This shows a small public invalidation and substantial native layout cost. It does not prove that all internal processing was limited to those ranges, that a whole-document scan is absent, or that a specific app callback is redundant. The initial construction/attachment and scroll stages consumed most of the case's 20-second allowance; it was not extended. The failed host requested termination and could force only its owned process if necessary; this case does not have a verified normal-termination result.

## Modern editor and viewport correction

The first TextKit 2 variant copied `EditorTab` and replaced its constructor and legacy scroll/glyph queries with public content-location and layout-fragment APIs. It preserved native direction handling, font fallback, text storage, delegate/status behavior and per-tab Undo. No legacy `layoutManager` property was read. In addition to editing checks, it required the independent saved text anchor and three-point offset, with the caret visible, before input and after each Undo.

ASCII completed all 20 checks. Mixed script failed the initial viewport assertion before any edit. A separate geometry-only follow-up showed that the requested anchor was 360464, but the captured anchor was 360299. The clip origin was about 241.28 points above the intended line after native layout settled. The paragraph fragment's document-relative range and its line's paragraph-relative UTF-16 range were internally consistent; this observation did not support changing the range-offset arithmetic.

A new variant completed `textViewportLayoutController.layoutViewport()` immediately after native scrolling and `sizeToFit()`, before reading the anchor geometry and applying the saved offset. It passed all 20 ASCII and all 20 mixed-script exact text/Undo/selection/viewport checks. The mixed anchor remained 360464; the settled offset was 3.220 points, within the unchanged one-point allowance of three. The modern engine remained present after every edit, so these cases did not fall back to TextKit 1. Images captured only each generated editor's own content view; the mixed fixture retained native right-to-left presentation and a visible caret.

| Complete isolated variant | Workload | Dispatch median / p95 |
| --- | --- | ---: |
| First modern viewport implementation | ASCII | 2.691 / 3.333 ms |
| Explicit viewport completion | ASCII | 2.568 / 3.947 ms |
| Explicit viewport completion | Mixed script | 56.516 / 57.983 ms |

These are synchronous app-local dispatch diagnostics, not physical event-to-visible measurements. They omit the complete workspace's tab/status/checkpoint integration and the original XCTest delivery path. The failed legacy case is not a before baseline. Even the complete modern mixed case exceeds the unchanged 16.7 ms numerical target; no production speedup is inferred from this table.

## Full-app experiment remains unaccepted

The private modern implementation was applied experimentally in the issue-45 worktree, with the original full AppKit fixtures and recovery assertions. The build and exact product sandbox checks passed. The first AppKit run passed three navigation tests, then the 20-hidden-tab test exceeded its unchanged 60-second maximum. Its new layout-state test helper enumerated every paragraph instead of stopping at the first unlaid fragment, which differed from the original `firstUnlaidCharacterIndex()` observation.

The failed run is `ModernIntegration-17467B85-C93B-42F2-83FF-197E35E8864C`. Its source and exact app/test binaries are retained alongside the logs and result. After the timeout and stalled finalization, only the identified `xcodebuild` received SIGINT. It exited 73 and reported interrupted testing plus an action-log publication error. The eventual result summary reports three passes, the timeout and a canceled-runner failure; it is incomplete and failed. No diagnostic stack sample of the timed-out test was obtained: ownership checks stopped both attempts before attachment.

The test observation was then corrected to stop at the first fragment without layout, preserving the former assertion's meaning without requesting estimates or layout. Application source, fixtures, recovery/byte assertions and 30/60-second limits were unchanged between these two AppKit experiments. The revised build passed, but its Xcode run `ModernIntegration-F66A9425-7F2F-4B2B-949C-73A4B0DEE3C2` did not start an AppKit case within a separately declared 300-second whole-command bound. The host sent SIGINT and then SIGTERM after another 30 seconds; the command exited from SIGTERM. A two-second sample of only its identified `xcodebuild` showed an idle event loop, without establishing the cause. That run provides no functional result for the revised helper or editor. Its source, binaries, logs, partial result and timeout record remain retained. No native test failure authorizes weakening the original invariants or changing the timeout.

The separate cold-launch harness subsequently passed against the experimental app. Its private host copy changed only failure-fixture retention and recorded the generated UUID; all original byte, file-event, dirty-recovery, restart, independent caret/logical-scroll checks and ten-second observation bounds remained intact. The app's exact sandbox signature passed before and after. This completed at 22:57:05 UTC; source/host/app hashes and output are retained in `modern-cold-4F87C787-6CBB-470F-9E84-9B5511EB5178`. It establishes those launch/recovery checks on this Mac, without replacing the failed or unstarted AppKit suite, full CI or performance protocols.

## Complete private workspace comparison and decision

A further predeclared comparison connected the production-derived `WorkspaceWindowController`, tab bar, status callbacks and checkpoint coordinator to each editor engine. Each case used two generated 1 MiB drafts and preserved all 20 planned dispatch observations within the same 20-second host limit. All four cases completed normally, with exact open-buffer bytes, independent selections, Undo, logical viewport and final checkpoint checks. The [complete records](2026-09-09-workspace-dispatch-diagnostics.json) retain source/driver/binary hashes and every observation.

| Engine | Workload | Dispatch median / p95 |
| --- | --- | ---: |
| Current TextKit 1 | ASCII | 2.805 / 5.435 ms |
| Current TextKit 1 | Mixed script | 41.366 / 43.299 ms |
| Experimental TextKit 2 | ASCII | 1.988 / 6.055 ms |
| Experimental TextKit 2 | Mixed script | 56.414 / 57.764 ms |

The private driver uses app-local input and direct per-tab Undo. It does not reproduce the original XCTest delivery/AX path, dirty-other-tab setup, two closed-history drafts, actual app delegate/menu startup or process-restart checks. Consequently these samples cannot replace, pool with or establish a speedup over the original #43 baseline. They do show that the engine replacement did not improve mixed-script dispatch in this isolated workspace comparison. The earlier legacy observer timeout remains a separate failed experiment.

The generated `.xctestrun` manifest was also tried once as a different AppKit driver path, avoiding project/package resolution. `ModernManifest-869020EF-FE16-4A22-8BC0-1050C0B524EF` still started no test before its declared 180-second command bound. Only that command received SIGINT, then SIGTERM after 30 seconds; the interrupted result remains retained. This rules out package resolution as a sufficient explanation for the observed startup stall, without identifying its cause or changing macOS authorization.

The experimental production/test edits have therefore been removed from the issue worktree after saving their exact source, patch and binaries. This report is a diagnostic-only change. No editor migration or typing-speed fix is selected for main, and #45 remains open. The isolated cold-launch pass remains valid for that retained prototype, but does not establish its full correctness or production performance.

Full functional CI, native Find/IME/accessibility behavior, complete unprofiled before/after interaction and launch protocols, archive checks and supported runtime/hardware evidence remain required. The production editor on main remains unchanged. Public APIs were checked in the installed AppKit headers and Apple's [TextKit documentation](https://developer.apple.com/documentation/appkit/textkit), [NSTextView compatibility boundary](https://developer.apple.com/documentation/appkit/nstextview) and [viewport layout controller](https://developer.apple.com/documentation/appkit/nstextviewportlayoutcontroller).
