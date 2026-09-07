# Combined M5 validation

Date: 2026-09-07. NoteHush 0.1.0 (1). Source `d4910767fae7e4d8e06ebd2c65170f930780a11d`, clean at each measured run. This integration combines the existing #43 measurement protocol, #46 hidden-editor scrollbar correction, #48 storage gate and #50 native folder-input setup, including the previously prepared direct/post-build interaction storage guards. Original issue branches and main remain unchanged and unmerged.

## Functional CI and retained failure

[Combined CI 34136196487](https://github.com/Orbitane-Limited/NoteHush/actions/runs/34136196487) failed. All 41 repository checks, 85 core tests, 166 Debug/Release crash-recovery drills and all 34 AppKit tests passed. The formerly failing hidden-editor regressions are green with the scrollbar correction. The native Find/Replace case failed to observe its expected original text after the first single replacement followed by Cmd+Z. XCTest spent approximately 10.15 seconds in that shortcut's synthesis before the unchanged ten-second value expectation expired; this is distinct from a one-minute whole-case timeout. The authoritative xcresult reports 61 total tests: 60 passed, one failed, zero skipped and zero expected failures. All 34 AppKit tests and 26 of 27 native UI tests passed.

Verification-log upload failed at CreateArtifact with `ENOTFOUND`; the GitHub artifact API reports zero retained artifacts for this run. Complete logs and `Lifecycle-82EE4C09-9812-4381-8531-3CC987E7EB03.xcresult` were copied from the still-matching runner checkout into root `build/validation-m5-d491076-failed/` before another test. The mounted-volume Save/Quit case passed in 21.771 s. Offline-volume testing and later builds were not reached in CI. No source/assertion/time-limit change or unconditional CI rerun was used to mask the failure. Full passing final-source CI remains required; the other #29 findings and release gates remain open.

The retained synthesized Cmd+Z record targets the identified isolated app process. This records the requested destination, not delivery to its editor. During each of the ten failed value observations, XCTest reported that it could not encode the editor debug-description attachment as UTF-8; the exported attachment contains that encoding error, not an editor value. No screenshot or unrelated window/system-dialog content was inspected.

The exact UUID associated with this failed test launch was resolved from its own session record. Both persisted schema-6 generations have valid manifest checksums and reference strictly decodable UTF-8 blobs with matching digest, byte count and UTF-16 count. Each contains the expected empty background tab and the exact first single-replacement fixture in the selected tab, with selection location 9/length 4. The two manifests and their referenced blobs are retained privately. This excludes malformed persisted fixture text in those generations, but cannot establish the final in-memory text, first responder, or whether Undo reached the editor. Normal recovery workspaces were not read.

The next bounded diagnostic must distinguish app-local Cmd+Z delivery, selected-editor focus and that editor's UndoManager notifications. Use fixed labels/Booleans only, require the isolated UUID workspace and compile any temporary hooks out of shipping Release and ReleasePerformance. Preserve every result with the existing assertions and time allowances; an unchanged rerun until green would not resolve the finding.

## Focused Find/Undo diagnostic

The unchanged complete Find/Replace/Undo case passed in 29.264 seconds on the same CI-built isolated app, executable SHA-256 `38c45bc1246f6a6590b19f3e7cde6471adad2ccdcfd9264cd3a26e028806b7df`. Exact product sandbox signatures passed before and after. Result: root `build/logs/FindFocus-C62FAC95-8283-4C26-B74A-D0DDB735F54B.xcresult`.

A temporary host-only probe sampled the identified test app's active state and the public secure-input Boolean every 100 ms, recording state changes only. It used no event tap, AX query, key capture, activation, global setting change or unrelated app/window contents. The target became active approximately 3.117 seconds after probe start and remained active until termination at approximately 30.710 seconds. Secure input was never observed enabled. The probe was stopped afterward and did not run during timing collection. It cannot establish the original CI failure's cause, first-responder state, or transitions shorter than the sampling interval. Its four private observations and exact test provenance remain in root `build/logs/focus-probe-C62FAC95-8283-4C26-B74A-D0DDB735F54B.jsonl` and adjacent files. No diagnostic hook was added to product code.

## Optimized launch comparison

All three unchanged launch cases passed, including 63 native launch/edit/Undo/Quit cycles, exact all-buffer/history verification, exact product entitlements and fixture cleanup. The strict exporter accepted all 120 observations: 20 samples for each of two intervals in each workload. Result `Performance-46BFC541-6DAD-47D0-B95E-A2A9B91C436A.xcresult` and complete logs remain in the integration checkout's `build/logs/`. The framework's single warm-up iteration is unchanged, and no additional sample is removed.

The launch build retained an existing deprecated `NSBox.borderType` warning and two App Intents metadata-extraction notices. Neither measurement log contains the earlier teardown-observer warning; no warning was filtered from the private logs.

| Workload | First-frame median / p95 | Editor-ready median / p95 |
| --- | ---: | ---: |
| Empty | 297.486 / 305.155 ms | 187.429 / 201.019 ms |
| 20 tabs, 5 MiB | 289.358 / 308.051 ms | 816.681 / 836.353 ms |
| 100 tabs plus history, 30 MiB | 299.666 / 329.586 ms | 1,996.418 / 2,023.273 ms |

First-frame and process-entry-to-editor-ready intervals overlap and must not be added. Readiness excludes pre-entry loader/LaunchServices work and is not physical display scan-out. This is warm-filesystem fresh-process testing, not post-reboot cold launch. The current 5 MiB readiness p95 is below its numerical one-second target on this Mac. Earlier pre-scrollbar integration observations were 1,012.042 ms for 5 MiB and 2,449.276 ms for 30 MiB; this separate run is not a controlled attribution of the difference to one code change.

## Optimized native interaction results

All four unchanged cases passed in a single native run: ASCII switch 212.757 s, mixed-script switch 212.430 s, ASCII typing 95.144 s and mixed-script typing 109.190 s. Exact all-buffer/history/selection/viewport verification, normal Quit/restart, exact product entitlements and fixture cleanup passed. The strict exporter accepted all 160 observations: 20 samples for each of two intervals in each workload. No run was retried and no slow observation was removed. Result: `Interaction-75ACB751-D813-45B7-A4C5-8748B01C4384.xcresult`.

| Workload | Native dispatch median / p95 | XCTest round trip median / p95 |
| --- | ---: | ---: |
| ASCII typing, 1 MiB | 1.051 / 1.209 ms | 31.548 / 38.389 ms |
| Mixed-script typing, 1 MiB | 197.043 / 200.417 ms | 237.913 / 273.929 ms |
| ASCII tab switch | 30.027 / 31.516 ms | 107.986 / 111.382 ms |
| Mixed-script tab switch | 75.871 / 76.924 ms | 131.549 / 140.884 ms |

Native dispatch measures the identified event's synchronous `NSApplication.sendEvent` interval; it excludes later display presentation. The XCTest interval includes input synthesis/automation work. These boundaries must remain separate from the PRD's physical event-to-visible typing and fully presented switch targets. Mixed-script typing dispatch alone exceeds 16.7 ms, and mixed-script switch dispatch exceeds 50 ms on this host. Issue #45 remains necessary; the passing protocol establishes reproducible measurements, not acceptable performance. No hot-stack attribution or optimization is claimed.

Raw metric values and initial conditions are retained in [launch metrics](2026-09-07-m5-integration-launch-metrics.json), [launch environment](2026-09-07-m5-integration-launch-environment.json), [interaction metrics](2026-09-07-m5-integration-interaction-metrics.json) and [interaction environment](2026-09-07-m5-integration-interaction-environment.json). These files contain generated measurements and host categories only. Complete xcresults and diagnostic logs remain private in ignored build directories.

## Conditions and remaining gates

Both protocols use the same clean source and optimized executable, SHA-256 `136562f63afe62149de261af8e4fbe102c5c3a30c0efb2f11494082a148ca3f2`. Host: M4 Pro, 24 GiB, macOS 26.6.2 (25G83), Xcode 26.6 (17F113), Swift 6.3.3, arm64, AC power, initial battery 76%, low-power mode off and initial thermal state 0. Battery charging-state text was not recognized and remains unknown. Displays were 1512×982 at 2×, 1440×2560 at 1× and 3440×1440 at 1×. Initial conditions are recorded, not continuously monitored.

The user acknowledged a further 60-minute awake/unlocked exclusive-input window at approximately 14:57 UTC. Actual human input was not continuously monitored. Functional CI had fully finished, the runner was idle and owned UI/performance/probe processes were absent before starting measurements. A GitHub runner-status EOF and a timed-out automatic permission review prevented earlier interaction launch requests from starting any tests; they contributed no timing samples. Fresh runner/process checks preceded the eventual native run.

## Additional engineering builds

After native measurements ended, the runner was confirmed online/idle. Debug build and `bash scripts/archive.sh` passed without launching the app. The Release archive contains both arm64 and x86_64; configuration verification checked version/build, bundle ID, macOS 14 deployment metadata, the packaged privacy manifest and exclusion of test-workspace/performance controls from the shipping executable. Archive executable SHA-256: `dcdb96b2dd3d7bd1a81acdf040c379995c4acc76c1be7b545d1b381f3e1dbd15`. The compiled source was unchanged from `d491076`; only the untracked validation report/JSON files were present.

Commands were the standard unsigned Debug `xcodebuild` invocation from `scripts/check.sh` and `bash scripts/archive.sh`. Logs are `build/logs/combined-debug-build.log`, `combined-release-archive-driver.log` and `combined-engineering-builds-provenance.json` in the integration checkout. These separate build results do not alter the failed CI conclusion. The archive is unsigned and is not ready for App Store submission.

Minimum M1/8 GB hardware, minimum-macOS/Intel runtime, physical event-to-visible latency, memory/energy, large-file/pathological-line behavior, VoiceOver/real IMEs, signing/TestFlight and App Store release gates remain unverified. Informational measurements do not override the failed functional CI or establish App Store readiness.
