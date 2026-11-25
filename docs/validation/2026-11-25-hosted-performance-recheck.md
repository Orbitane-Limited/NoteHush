# Hosted performance recheck — 2026-11-25

Issue #12. Workflow: [run 45508609236](https://github.com/Orbitane-Limited/NoteHush/actions/runs/45508609236). The workflow measured baseline `b52816792a3acd5e3aa6360ad26329e209bee126` and current `main` `d0b5ba4288923315cb0927d351ea387202d3805c` sequentially on one fresh GitHub-hosted VM. Both suites completed with 20 samples per scenario and retained their raw result bundles and logs in the workflow artifact.

## Launch and restoration

Host: `VirtualMac2,1`, arm64, 7 GiB RAM, 3 logical CPUs, macOS 26.7.2 (25G332), Xcode 26.6, Swift 6.3.3. This is a hosted virtual Mac, not a physical M1/8 GiB reference device. Filesystem caches were warm after fixture preparation. `ProcessToEditorReady` ends after recovery, editor setup, focus, layout and `displayIfNeeded`; it does not measure display scan-out. `ApplicationLaunch` is the separate first-frame metric.

| Current-main workload | Process-to-editor-ready median | p95 | PRD target comparison on this VM |
| --- | ---: | ---: | --- |
| Empty workspace | 548.845 ms | 704.986 ms | Above 500 ms target |
| 20 tabs, 5 MiB | 814.939 ms | 925.313 ms | Within 1 second target |
| 100 open + 20 closed tabs, 30 MiB | 1,621.900 ms | 2,234.400 ms | Stress result; no separate PRD budget |

The measured empty-workspace p95 exceeds the PRD target in this run, while the 20-tab/5 MiB p95 remains within target. These virtual-runner observations do not establish physical M1/8 GiB performance. The 30 MiB workload is stress coverage, not a substituted acceptance threshold. A 10 MiB opening benchmark is tracked separately in #73.

The pre-existing 2026-10-24 hosted comparison used the same virtual model on macOS 26.6.2 and reported a 262 ms candidate editor-ready p95 for an empty workspace. This recheck used macOS 26.7.2. App and core source files are identical between the compared revisions; the comparison does not attribute the current difference to a product-code change. Treat it as an environment-sensitive observation pending matched physical hardware and repeatability evidence.

All 20 samples and source/environment provenance are retained in [`2026-11-25-hosted-performance-recheck/`](2026-11-25-hosted-performance-recheck/). The full `.xcresult` bundles, build/test logs and fixture evidence are retained locally under `build/issue12-launch-current-comparison/`; the workflow retains its artifact for seven days.

## Typing and tab-switch dispatch

The same hosted comparison workflow ran the interaction suite in [run 45511174731](https://github.com/Orbitane-Limited/NoteHush/actions/runs/45511174731), again with 20 samples for each scenario and sequential baseline/current-main revisions on one VM.

| Current-main workload | App dispatch median / p95 | XCTest clock median / p95 |
| --- | ---: | ---: |
| ASCII typing | 2.424 / 2.905 ms | 47.802 / 64.249 ms |
| Mixed-script typing | 2.589 / 3.950 ms | 41.942 / 52.713 ms |
| ASCII tab switch | 15.480 / 21.832 ms | 143.660 / 156.509 ms |
| Mixed-script tab switch | 12.868 / 18.580 ms | 109.447 / 120.499 ms |

The app-dispatch interval measures synchronous `sendEvent` processing. The XCTest clock interval also includes automation and event delivery. Neither interval measures physical input-to-visible latency or deferred display; the PRD's 16.7 ms typing and 50 ms tab-switch targets therefore remain unverified. The 2026-10-24 hosted comparison used macOS 26.6.2; this run used 26.7.2, so cross-run differences do not identify a product-code regression. All 20 observations and provenance are in the adjacent interaction JSON files. Full logs and results are retained locally under `build/issue12-interaction-current-comparison/`; the workflow artifact is retained for seven days.

## Remaining #12 acceptance

This run does not measure physical input-to-visible typing latency, idle CPU/energy, RSS acceptance, Instruments attribution, large-file editing, font/zoom/wrap/print responsiveness, or 100-tab history-management latency. It does not cover macOS 14, Intel, or a physical M1/8 GiB device. Keep #12 open; do not describe this hosted run as complete performance acceptance.

## Hosted Allocations diagnostic

A separate generated-fixture [Allocations workflow](https://github.com/Orbitane-Limited/NoteHush/actions/runs/45512598573) completed two 60-second traces on the same current-main source and hosted VM configuration. The trace ran with `MallocStackLogging=lite` so it could retain bounded source backtraces. It verifies exact app identity, normal termination and fixture recovery, but the instrumentation changes memory use substantially.

| Generated workspace | All Heap & Anonymous VM, persistent | All Heap Allocations, persistent |
| --- | ---: | ---: |
| Empty | 255,142,752 bytes (243.30 MiB) | 9,677,664 bytes (9.23 MiB) |
| 20 tabs, 5 MiB | 501,016,592 bytes (477.83 MiB) | 28,092,432 bytes (26.79 MiB) |

These are instrumented Allocations totals, **not RSS or physical-footprint measurements**. The 20-tab trace is 245,873,840 bytes higher in this combined allocation category; it does not isolate text storage from AppKit or other system allocations. The largest bounded directly attributed NoteHush allocations were the same in both traces: 20,480 bytes from `TabBarView.reveal(_:)`, 2,560 bytes from `PerformanceApplication.sendEvent(_:)`, then 1,280-byte scroll-view allocations, a 1,024-byte text-view allocation and 768-byte view/button/stack allocations. This sample does not identify a large NoteHush-owned allocation that supports a production source change; it is not a complete ownership accounting.

The workflow retains raw traces for three days. A compact path-free extraction of sample counts and largest directly attributed allocations is in [`hosted-idle-allocations-summary.json`](2026-11-25-hosted-performance-recheck/hosted-idle-allocations-summary.json). This is diagnostic context only; the failed/incomplete physical RSS attempts remain unaccepted, and idle CPU/energy plus physical reference hardware are still open.
