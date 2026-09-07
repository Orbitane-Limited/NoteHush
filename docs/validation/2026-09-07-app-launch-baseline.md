# Initial native-app launch baseline

Issue [#35](https://github.com/Orbitane-Limited/NoteHush/issues/35). Engineering version **0.1.0 (1)**. The complete isolated measurement protocol passed on 2026-09-07. This establishes an informational M4 Pro baseline; it does not accept the PRD performance budgets or close parent #12.

## Source and conditions

- Clean source: `14090474bf632b3705acf7c005b00c1b8bad60ac`, including merged recovery #31 and editor-layout #39.
- Optimized executable SHA-256: `2e08dfbdbd75b022402abc9574d3767a97e41934705d0bb6043b2f080789bc15`.
- macOS 26.6.2 (25G83), Xcode 26.6 (17F113), Swift 6.3.3, arm64; M4 Pro, 24 GiB, 12 logical CPUs.
- AC power, low-power mode off, initial thermal state **fair (1)**; one 3440 × 1440-point display at scale 1. These are initial conditions, not continuous power/thermal monitoring.
- Provenance captured at 02:58:46 UTC; XCTest finished at 03:04:03 UTC. NoteHush CI was complete and the runner idle before this run. No other NoteHush GUI automation or profiling ran concurrently. Other human/application input exclusivity was not independently verified.
- Fresh app processes with warm filesystem caches after fixture preparation; no post-reboot cold-start claim. Swift `-O`, whole-module optimization and debugger-disabled scheme verified before launch.

Complete [sanitized provenance](2026-09-07-app-launch-environment.json) and [all metric samples](2026-09-07-app-launch-metrics.json) are committed. The metric JSON retains every reported observation, original seconds units, exact interval identifiers, counts, median and nearest-rank p95; it excludes raw xcresult device identifiers.

## Results

Every row below contains **20 measurements**. XCTest ran one additional warm-up per workload and excluded it; the exporter discarded no further observations and accepted no retries. Values below are milliseconds, converted from the retained seconds samples.

| Workspace | Apple first-frame median | First-frame p95 | Entry-to-editor-ready median | Readiness p95 |
| --- | ---: | ---: | ---: | ---: |
| Empty tab | 286.833 | 362.876 | 198.042 | 267.138 |
| 20 open tabs, 5 MiB | 271.471 | 309.779 | 1,904.724 | 2,237.930 |
| 100 open + 20 closed tabs, 30 MiB | 270.351 | 287.608 | 3,016.358 | 3,087.787 |

Apple's `XCTApplicationLaunchMetric(waitUntilResponsive: false)` measures first-frame launch (no MetricKit extended launch tasks are started). `ProcessToEditorReady` begins inside the app entry point after the required workspace guard and ends after recovery, selected-editor presentation, key-window input focus, layout and `displayIfNeeded`. The latter excludes pre-entry loader/LaunchServices work and is not display scan-out or event-to-visible typing latency. The intervals have different boundaries, may overlap and must not be added together. First-frame display can precede asynchronous recovery.

The 5 MiB readiness result exceeds the PRD's one-second restoration target even on this M4 Pro. It directs further investigation; no target was relaxed. The reference M1/8 GB, post-reboot launch, typing, tab switching, memory/idle energy, large-file/display/printing/history workloads and supported-OS/architecture gates remain open.

## Executed validation

`bash scripts/test_performance.sh` exited zero. All three cases passed: empty 94.251 seconds, 5 MiB 100.430 seconds, 30 MiB 119.712 seconds. These are whole-test durations, not launch samples.

- Required UUID rejection, host-generated fixture setup, optimized build settings and exact four-entitlement sandbox signatures passed.
- All **63** fresh-process launches passed the readiness marker, selected-tab identity and restored-text digest checks. Each accepted a generated keyboard edit, undid it to the original digest, and terminated through Cmd+Q with both XCTest state and the owned process stopped.
- After the final normal termination, host verification passed exact ordered open/closed tab identities, all text digests, selected tab and advanced recovery revision for every workload. Fixture cleanup passed.
- CSV and raw JSON export succeeded. The strict summarizer accepted exactly the two documented metric identities, seconds units and 20 finite nonnegative values per interval in all three cases. It rejects missing/extra intervals, changed units, short samples and retried runs.
- The log retains **17** `Unable to monitor event loop` diagnostics, all during Tear Down after measurements: 8 empty, 7 at 5 MiB, 2 at 30 MiB. Their underlying cause is unverified. They did not omit samples or fail this run; none were suppressed.
- The 28 repository automation tests, strict Swift formatting, configuration verification and whitespace checks passed locally before this run. Full regression CI remains the PR merge gate.

Raw evidence remains in `build/logs/Performance-86F47005-FB67-41AF-9351-4EF77942BAA9.xcresult`, its adjacent `-metrics/`, `-raw.json`, `-summary.json` and `-environment.json`; full command log: `/tmp/notehush-issue35-first-frame-full.log`. Prior failed responsive-launch runs are retained in the [investigation](2026-09-07-performance-harness-setup.md). They are not pooled or relabeled as first-frame results.

## Separate app-only profile

The [verified attachment protocol](2026-09-07-performance-harness-setup.md#verified-attached-profiling) passed on clean source `61cce9f505ca194411f0b03dfb2c966fd0a20b3f` with the **same executable SHA-256**. Recorder success, exact target ownership, normal termination, complete fixture verification, TOC export and cleanup passed. `PerformanceAttached-55C52A34-6B51-4AA1-B3A8-4F90597212AA.trace` retains the raw evidence.

All 465 sample rows belong to the intended app; 422 are main-thread samples. Of those, 360 contain `NSTextView` becoming first responder, 359 contain bounding-rectangle layout and 348 contain bidirectional processing. These cumulative stacks overlap; they are diagnostic sample counts, not durations. They point to selected-editor focus/layout for the next investigation. Attachment began after LaunchServices startup and lasted about 10.72 seconds, so it misses earlier startup work and cannot establish complete launch or settled idle CPU. No performance result was collected under the profiler.
