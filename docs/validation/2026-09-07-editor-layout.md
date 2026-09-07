# Restored-editor layout investigation

Recorded 2026-09-07 for [#39](https://github.com/Orbitane-Limited/NoteHush/issues/39). The isolated optimized launch workload in [#35](https://github.com/Orbitane-Limited/NoteHush/issues/35) exposed a main-thread editor-construction stall. This report separates that application defect from the UI interruption investigation in [#29](https://github.com/Orbitane-Limited/NoteHush/issues/29) and the complete performance acceptance in [#12](https://github.com/Orbitane-Limited/NoteHush/issues/12).

## Before the fix

The failed full launch run used clean source `8ee1ee57a80d1f60208674a57f63784dbae19c1d`, including merged recovery source `692ca3f4fdef76ae85b7c907a52194ccad705123`. The native arm64 performance executable was compiled with `-O` and whole-module optimization, without a debugger, and signed with exactly the four product sandbox entitlements. Its SHA-256 was `85c442e7d8669b0b04a77f3df2d5874bf1051cf0ec6115de1f562f912700d170`. `EditorTab.swift` was byte-identical to main (SHA-256 `82c1381f067534dcb7beb8e1bad7a29c8351e4f0ebebf9f903edd568e0d92484`).

CI had fully completed before the run began at 01:06:37 UTC. The empty-workspace case completed, but the first 5 MiB launch could not supply an editor accessibility snapshot. The workspace contained 20 open 256 KiB tabs, alternating unique ASCII and Arabic/combining-mark/emoji CRLF drafts; the final mixed-script tab was selected. The 30 MiB case was never reached. These partial measurements are not an accepted baseline.

At 01:10:53 UTC, a three-second sample of only the identified fixture app process showed all 2,282 main-thread samples below `WorkspaceWindowController.loadWorkspace` → `EditorTab.init` → `NSScrollView.setDocumentView` → TextKit layout-hole filling and bidirectional writing-direction processing. The process was using 100% CPU almost three minutes after launch. The sample did not inspect another app or a normal NoteHush workspace.

Evidence remains locally in the issue-35 worktree:

- `build/logs/Performance-E294918A-D8CC-43F3-BCC9-CEBDA4166E02.xcresult` and adjacent environment JSON.
- `/tmp/notehush-issue35-full-performance.log` and `/tmp/notehush-issue35-five-mib-sample.txt`.

The identified test invocation was interrupted after diagnosis and Xcode exited 73 during finalization. The fixture app had stopped before cleanup checked it, and cleanup of the generated UUID workspaces passed.

## Isolating the trigger

Bounded in-memory AppKit probes used the same 256 KiB mixed-script draft on this M4 Pro/24 GiB Mac with macOS 26.6.2, Xcode 26.6 and Swift 6.3.3. They created no normal workspace and displayed no window. Each diagnostic process had a 15-second bound; only that owned probe process could be stopped.

| Probe | Observation |
| --- | --- |
| Assign text, then attach to a zero-sized scroll view | Did not finish attachment within 15 seconds |
| Assign text, then attach to a 900 × 500 scroll view | Did not finish attachment within 15 seconds |
| Attach empty editor, then assign text, sized scroll view | Completed in about 0.066 seconds |
| Attach empty editor, then assign text, zero-sized scroll view | Completed in about 0.058 seconds |
| Empty-first attachment followed by explicit full-container layout | Did not finish full layout within 15 seconds |
| Empty-first attachment, noncontiguous layout and visible-range layout | Completed without laying the whole document |

These single-run diagnostics identify initialization order and explicit full layout as separate triggers. They are not 20-sample app timings. Probe source, executable and logs are retained under `/tmp/notehush-editor-layout-*`.

## Change and deep-scroll regression

The editor attaches while empty, with an initial positive viewport size, then applies preferences and recovered text. Each layout manager allows noncontiguous layout and disables idle background layout. Restoration uses native `scrollRangeToVisible` for the saved text anchor, sizes the document and then applies the saved offsets. No full-container layout is requested. TextKit can still expand requested ranges; this does not guarantee cheap layout for every paragraph or large file.

A first local suite passed all 33 AppKit cases, including a selected draft at its start. Strengthening the fixture to put the caret near the end exposed a real scroll error: requesting only the anchor character left the viewport at y=45,021 while the caret was near y=48,788. Moving the line lookup after sizing did not fix it. Native anchor scrolling kept the caret visible.

The first restart assertion compared absolute scroll y and failed by 94 points. Generated-geometry diagnostics showed that both the saved text line and viewport shifted by exactly 94 points as TextKit changed its estimated total document height: before restart, line y=48,259 and viewport y=48,279; afterward, line y=48,165 and viewport y=48,185. Both preserve the same four-point offset after the 16-point text inset. The final regression compares the identical text anchor and caret within the viewport with the original one-point tolerance. It also checks exact UTF-8, UTF-16 selection, tab order, hidden layout state and checkpoint/reopen behavior. Diagnostic prints were removed from test and application source.

Earlier failures remain in `EditorLayout-Deep`, `EditorLayout-Geometry`, `EditorLayout-Anchor`, `EditorLayout-NativeScroll` and `EditorLayout-ReopenAnchor` result bundles in the issue-39 worktree. No timeout was raised and no failing application behavior was accepted as a pass.

## Validation status

All 33 AppKit tests passed in the isolated `DebugUITesting` build after the final scroll correction (16.24 seconds total; hidden-editor regression 1.34 seconds; deep-scroll/reopen regression 8.59 seconds). Build-for-testing and strict product-entitlement signature verification passed. Result bundle: `build/logs/EditorLayout-FinalAppKit.xcresult`; log: `/tmp/notehush-issue39-final-appkit.log`. Final editor source SHA-256: `43d089de6cecc33a6842ae20e05d7d445ee4660b9f7e1edae00ea2644fccb510`.

The optimized app then completed all 63 fresh launches across the empty, 5 MiB and 30 MiB workloads (21 per case, including XCTest's warm-up), with exact selected-text/tab checks, real edit/Undo and Cmd+Q termination checks on every launch. This diagnostic run used clean measurement source `dc9400181d275a25768c2fd5567b1c12b35ec484`, containing editor source `1db0fdd48fb5a9af4516e871807a66846bdd69e7`; executable SHA-256 `fb580020706f7b367c3fc498fe7050e4e1436325d8035431ff3e6cc00280bc83`. CI was fully idle. Empty and 30 MiB measurement cases passed; 5 MiB metric aggregation failed because some iterations supplied only one of the two requested metrics. Its exported distributions contain four samples, so the strict summarizer rejected the run. The app's functional assertions passed, but final host all-buffer verification was not reached after xcodebuild returned 65. Fixture cleanup passed. No complete timing baseline is claimed. Evidence: issue-35 `build/logs/Performance-4AB8B104-A552-4D52-9BCC-314048739FBF.xcresult`, adjacent environment/raw JSON, and `/tmp/notehush-issue35-layout-performance.log`.

A subsequent app-only Time Profiler trace targeted the uniquely named performance executable, with the same byte-identical editor source. The exported single-target table contains 2,579 samples and reaches `EditorTab.init`, `restoreScroll`, `WorkspaceWindowController.loadWorkspace` and the editor-readiness probe, unlike the earlier prolonged attachment stall. However, the profiler helper rejected completion with a generic error that does not distinguish recorder exit status, process observation or trace presence. The trace records that target ending with SIGKILL. Its buffer verification was not reached; fixture cleanup passed. Retain this as partial diagnostic evidence, not a validated profiling protocol or a normal-Quit result: `PerformanceLaunch-284019F6-B4BA-42FD-A901-A2D7C2E1046F.trace`, adjacent TOC and single-target time-profile XML, and `/tmp/notehush-issue35-unique-profile.log`. #35 owns readiness collection and profiler validation corrections; no product entitlement was added. Self-hosted [CI run 34074285817](https://github.com/Orbitane-Limited/NoteHush/actions/runs/34074285817) passed on source `908859d1ad271d0adcbaed0204c8e3ddd6bed682`. Its validation step ran 01:50:28–01:59:28 UTC and passed 15 repository-automation tests, 85 core tests, 33 AppKit tests, 28 UI scenarios, all 83 Debug plus 83 Release crash drills, cold-launch guards/file-event/dirty-restart checks, exact sandbox signatures, both mounted/offline volume cases, Debug build and the universal Release archive. Verification artifact `10001674924` and unsigned archive artifact `10001677029` use synthetic merge SHA `60a6890f0f102488e9432fa214b6d111ce44125f`. A local copy of the logs is retained at the root checkout's `build/validation-issue39-908859d/logs`. The final documentation commit must pass the same checks before merge; its exact-head result belongs in PR #40.

The M1/8 GiB reference machine, macOS 14/Intel runtime, VoiceOver, real keyboard IMEs, worst-case lost-input interval, typing/tab-switch/Open budgets, memory/energy and distribution signing remain open gates. This fix does not certify Mac App Store readiness or authorize a production release.
