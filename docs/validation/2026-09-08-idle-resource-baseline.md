# Complete settled CPU and memory baseline

Date: 2026-09-08 UTC / 2026-09-09 PKT. Issue #56, parent #12. Clean source `5f2d32cdbc2c10a0206a16f0cd4ede99f2bd1842`; isolated optimized executable SHA-256 `37fb1ce6509d160a14719eee4ee98981958cc434276830782c211989d2728ce5`. This records a complete native collection on the prepared issue branch, not merged-main CI or overall release acceptance.

The operator ran `NOTEHUSH_EXCLUSIVE_INPUT=1 bash scripts/measure_idle_resources.sh` after the previous CI job finished uploading and the dedicated runner was confirmed idle. The owner had confirmed an eight-hour exclusive window beginning at 22:04:56 UTC. No other agent-started native test, compiler, app or profiler ran during collection; small documentation/GitHub operations continued. Exclusivity was declared by the owner, not inferred from a passing result or independently monitored.

The original failed idle attempt remains untouched. This new run used fresh UUID fixtures, the same two workloads, 30-second settling interval, 61 readings and all existing identity, activity, normal-termination, exact-buffer and viewport assertions. It did not use XCTest or synthesize keyboard/mouse input, so the separate Automation Mode prerequisite for the queued UI suite was not involved or bypassed.

## Complete result

Both empty and 20-tab/5 MiB cases completed. The app was active at all 122 observations, quit normally after each case, and preserved every open/closed buffer, order, selection, preference and logical viewport. Exact sandbox verification passed before and after collection. The source remained clean and unchanged, and the final executable hash matched the initial provenance. The script and strict summary both returned success. No sample was removed or replaced.

| Workload | Elapsed collection | Average CPU, one core = 100% | RSS, min/median/p95/max | Physical footprint, min/median/p95/max |
| --- | ---: | ---: | ---: | ---: |
| Empty | 62.499 s | 0.001759% | 99.984 MiB | 29.548 MiB |
| 20 tabs, 5 MiB | 62.364 s | 0.002127% | 149.234 MiB | 73.392 MiB |

Each memory counter was constant throughout its own window, hence equal minimum/median/p95/maximum values. RSS and physical footprint are deliberately reported separately. CPU uses the recorded Mach timebase 125/3 and actual elapsed time, without dividing by the machine's 12 logical CPUs. All raw counters, interval CPU values, timestamps, units, source/binary provenance and initial conditions are preserved in the [complete baseline JSON](2026-09-08-idle-resource-baseline.json).

The less-than-1% CPU target is met for both recorded windows on this Mac. The 150 MiB resident target is met narrowly for 20 tabs. The **80 MiB empty resident target is not met**: it is exceeded by 19.984 MiB. The lower physical-footprint number does not replace the PRD's resident-memory requirement. Parent #12 remains open for that result and the other performance gates; this report claims no memory optimization or battery/energy result.

## Conditions and retained artifacts

M4 Pro, 24 GiB, arm64; macOS 26.6.2 (25G83); Xcode 26.6 (17F113), Swift 6.3.3. At fixture preparation: AC power, battery 80%, low-power mode off, nominal thermal state, and three displays (1512×982 points at 2×, 1440×2560 at 1×, 3440×1440 at 1×). Processes were fresh; filesystem caches were warm. Initial thermal/power state is not continuous monitoring.

The private run directory is `build/logs/Idle-F0F2C3B1-4E4A-4B47-9063-65BDEF64396F` in this issue worktree. It retains both raw JSONL recordings, environment, manifest, collection log and summary. Generated recovery workspaces remain retained; no normal NoteHush workspace was opened. The complete operator log is `build/logs/idle-window-20260908T2215Z.log`.

This is one process/window per workload, not 20 independent launches. M1/8 GiB, macOS 14/Intel runtime, physical energy, typing/switching, large-file/display/printing/history workloads and installed TestFlight remain separate acceptance work. PR #60 must merge before this PR, and full final-head functional CI/review is still required before closing #56.

The current-main physical recheck attempts from 2026-10-30 are recorded separately in [the failed profiling and partial idle-collection report](2026-10-30-idle-memory-recheck.md). Neither attempt supersedes this complete 2026-09-08 baseline.
