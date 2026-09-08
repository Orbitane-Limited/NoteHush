# Native interaction profiling and retained failures

Date: 2026-09-08. Issues #12, #29 and #45. Profiled source: clean `984df3737918b38120eb66b968511d1dfd26e391` on the separate `validation/v1-preparation` branch. This report records diagnostic evidence; it does not establish performance acceptance, final CI or App Store readiness.

## Product and conditions

The combined source includes the pending issue branches and the Settings-close correction from #55. All 36 combined AppKit tests passed in 21.521 seconds with the existing 30/60-second limits. Exact sandbox verification, the complete native ColdLaunchHarness, normal Debug, universal unsigned Release archive and optimized isolated performance build passed. The archive executable SHA-256 is `239fe4a651b6fcc4a800f3ab2d297c75ed0baa28407b19e34543961b5fffdbb7`.

Profiling used only the generated `pk.codehub.NoteHush.PerformanceTesting` app, built with Swift optimization and no debugger. Its executable SHA-256 is `a8f394cd2fa802b4f04a4c82fa45bde6c64fb290ad8e5fad086bfd9d9897d06f`. The product's exact four sandbox entitlements were verified. The host opened the exact app URL with a generated workspace UUID and verified the returned bundle URL, identifier and PID before attaching Instruments. No normal NoteHush workspace or unrelated process was opened or profiled.

Machine: M4 Pro, 24 GiB, arm64, macOS 26.6.2 (25G83), Xcode 26.6 (17F113), Swift 6.3.3. Initial conditions: AC power, 80% battery, low-power mode off, nominal thermal state; screens 1512×982 points at 2×, 1440×2560 at 1× and 3440×1440 at 1×. Filesystem caches were warm. These are initial observations, not continuous thermal monitoring. The user authorized a ten-hour exclusive-input window, but later unexplained input makes continuing exclusivity uncertain. No NoteHush CI job was queued or running when checked after the failure. The minimum M1/8 GiB reference machine was unavailable.

## Every recording attempt

| Attempt | Declared work | Recording and verification outcome |
| --- | --- | --- |
| Typing, initial 60-second Time Profiler | 20 generated key/Undo pairs in the mixed-script fixture | Recorder completed, dispatch counter 20, normal Quit and all-buffer/selection/viewport verification passed. The default template omitted the custom Interaction markers; this trace cannot support interval-aligned analysis. |
| Typing, 60-second Time Profiler plus `os_signpost` | Same 20 pairs, two fixed batches of ten | Recorder completed, exactly 20 nonoverlapping TypingEventDispatch intervals, normal Quit and exact fixture verification passed. Analysis below uses this trace only. |
| Switching, initial 60-second recording | 20 planned round trips between ASCII tab 19 and mixed-script tab 20 | After ten attempted round trips the counter was 19, not 20. The remaining ten were not attempted. Recorder completed; four separately observed actions after recording were excluded from the profile. Normal Quit and exact all-buffer verification passed. The declared workload was incomplete. |
| Switching, serialized 360-second recording | One warm-up outside recording, then 20 round trips with fresh state before and exact receipt after every action | All 40 receipts matched counter/selected-tab/focus expectations. The recorder failed to finalize within 30 seconds after its declared duration; only its owned recorder was interrupted/stopped. Normal app Quit succeeded, but exact fixture verification failed. The partial trace and both recovery generations remain retained; no accepted metrics were extracted. |

No run was retried until green, slow observations removed, assertion weakened or functional timeout increased. These separately declared investigations have different setup/observation behavior and are not interchangeable performance samples.

## Typing profile evidence

All 1,487 exported CPU sample rows and all 360 signpost rows belonged to the intended fixture process. Exactly 20 typing-dispatch intervals were identified by their fixed subsystem/category/name. Of 573 CPU samples inside those intervals, 572 were on the main thread.

| Inclusive main-thread stack observation | Samples, out of 572 |
| --- | --- |
| Native bidirectional layout / statistical writing directions | 508 |
| Insertion-point rectangle update using the layout manager | 521 |
| Layout for a bounding rectangle | 518 |
| App's text-change callback | 8 |

Counts overlap: a sample can contain every frame in a call chain. This is evidence that native caret/layout work dominates this trace, not proof that any particular requested range is redundant. It does not justify forcing left-to-right layout, changing Unicode behavior, suppressing caret updates or choosing a TextKit replacement without further evidence. The 20 instrumented dispatch durations are retained in the companion [diagnostic data](2026-09-08-interaction-profile.json); they exclude display scan-out and must not replace unprofiled acceptance timings or be compared as a speedup against the earlier XCTest baseline.

## Unexpected input and stopping condition

The serialized switching setup produced two computer-use state-refresh notices. Fresh observations showed that those affected commands had not been delivered, after which the one declared warm-up completed. Later all 40 per-action receipts matched, yet final byte verification found one extra byte exactly at the ASCII tab's original caret. All remaining bytes matched. The unexpected byte was never printed or logged. The mixed-script text remained byte-identical, but its caret and logical scroll anchor moved. Other open buffers and all closed buffers matched. Both retained schema-6 generations had valid checksums.

This does not attribute the change to the user, another automation, event delivery or the app. All owned fixture apps were terminated normally. Keyboard-driven validation was paused and the user was asked to clarify possible competing input. The failed workspace was neither reset nor removed. A host reporting command initially continued after the verifier returned nonzero and temporarily marked recovery passed; that local record was immediately corrected to failed. No passing result from it was published. Future dependent host commands must stop on any failed verifier.

Issue #29 now has a separately built [input diagnostic extension](2026-09-08-input-diagnostic.md), excluded from shipping/performance products. Its event-source metadata cannot retrospectively attribute this run. Issue #45 still requires its #43 dependency, a trustworthy unprofiled baseline, a justified correction and complete preservation checks. Full CI/review, all release performance budgets, supported hardware/OS, accessibility, real IMEs and signed TestFlight remain open.

Private evidence in this validation checkout includes the four `.trace` bundles, exact environment and executable identity, per-attempt plans, CPU/signpost exports, analysis, 40 action receipts and sanitized recovery-failure classification under `build/logs`. Raw trace environment data is not published. The old successful switching trace pointer remains distinct from the later partial trace; its presence does not establish the later recording succeeded.
