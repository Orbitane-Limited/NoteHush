# Schema-6 recovery comparison

Recorded 2026-09-07 Asia/Karachi (JSON completion 2026-09-06T23:02:38Z) for [#31](https://github.com/Orbitane-Limited/NoteHush/issues/31), compared with the committed [schema-5 baseline](2026-09-07-recovery-baseline.md). This measures the storage migration; whole-app performance remains [#12](https://github.com/Orbitane-Limited/NoteHush/issues/12).

## Build and conditions

- Benchmark source: `3b0f8a994a5dbe7922bd2a2cf4dabf29ccc8238f`, storage schema 6, app 0.1.0 (1). Executed binary SHA-256: `e0d4ce5869c4c44674753e1144d08f40a04c04fc3a5e2fd1694a546e4f134a15`.
- Same M4 Pro Mac16,8, 24 GiB memory, 12 logical processors and macOS 26.6.2 (25G83) as the baseline. Xcode 26.6 (17F113), Swift 6.3.3, native arm64 SwiftPM Release, no debugger.
- AC power, Low Power Mode off. CI run 34064376130 and the local AppKit/cold-launch tests had completed; the runner API confirmed online/idle before measurement. Other projects were not stopped. Thermal state was not recorded. Timings remain informational on a shared Mac.
- Same generated 5 MiB and 30 MiB workloads, 256 KiB per tab, alternating ASCII and Arabic/combining-mark/emoji CRLF fixtures and unique prefixes. Same 20 samples per operation, warm filesystem caches, fresh store for each restore, reused store for commits, mutation outside timing and exact canonical-byte recovery verification outside timing.
- Benchmark report schema 2 adds counts for fingerprint lookups, directory listings and removals. Workloads, duration/byte/write-count boundaries, median and nearest-rank p95 calculation are unchanged. Counters describe calls at the RecoveryFiles boundary, including its instrumentation overhead; they do not measure physical device traffic or all internal filesystem syscalls.

```sh
swift build -c release --product RecoveryBenchmark
.build/release/RecoveryBenchmark > build/recovery-schema6.json
```

## Results

All 120 timed operations and untimed recovery comparisons completed successfully. [Raw JSON](2026-09-07-recovery-schema6.json) retains all samples. An independent Python check verified every 20-value distribution, finite nonnegative values, middle-pair median, nineteenth sorted p95 and expected atomic-write counts (0 restore, 2 metadata-only, 3 one-tab edit).

| Workspace | Operation | Median ms | p95 ms | Median read MiB | Median write MiB |
| --- | --- | ---: | ---: | ---: | ---: |
| 20 open / 5 MiB | restore | 31.64 | 32.23 | 5.012098 | 0.000000 |
| 20 open / 5 MiB | selection-only | 2.21 | 2.37 | 0.012100 | 0.012103 |
| 20 open / 5 MiB | one-tab-edit | 3.04 | 4.45 | 0.012104 | 0.262107 |
| 100 open + 20 closed / 30 MiB | restore | 189.86 | 193.33 | 30.071934 | 0.000000 |
| 100 open + 20 closed / 30 MiB | selection-only | 7.85 | 8.04 | 0.071939 | 0.071941 |
| 100 open + 20 closed / 30 MiB | one-tab-edit | 8.41 | 9.44 | 0.071940 | 0.321945 |

For the 30 MiB workload, selection-only p95 fell from 1,021.87 ms to 8.04 ms; one-tab-edit p95 fell from 950.56 ms to 9.44 ms; restore p95 fell from 671.54 ms to 193.33 ms. Selection changes read/write about 0.072 MiB of manifests instead of about 90.036 MiB of complete encoded generations. A one-tab edit writes those manifests and the changed 256 KiB blob. Restoration still reads and verifies every distinct referenced blob; it is not a warm in-process-cache shortcut.

| Workspace | Operation | Median atomic writes | Fingerprint calls | Directory listings | Removals |
| --- | --- | ---: | ---: | ---: | ---: |
| 20 open / 5 MiB | restore | 0 | 40 | 0 | 0 |
| 20 open / 5 MiB | selection-only | 2 | 40 | 1 | 0 |
| 20 open / 5 MiB | one-tab-edit | 3 | 42 | 1 | 1 |
| 100 open + 20 closed / 30 MiB | restore | 0 | 240 | 0 | 0 |
| 100 open + 20 closed / 30 MiB | selection-only | 2 | 240 | 1 | 0 |
| 100 open + 20 closed / 30 MiB | one-tab-edit | 3 | 242 | 1 | 1 |

A first edit can leave both old and new text reachable from the two generations. Subsequent edits reclaim revisions that neither generation references; the median removal count is one in this alternating-tab workload. Separate I/O regressions require zero blob reads/writes for warm metadata commits and one blob write for a one-tab change. File fingerprints are validated against device/inode, size, permissions/ownership and nanosecond modification/change timestamps; fresh load verifies real checksum bytes.

## Validation and limits

At measurement time, 85 core tests, all 31 AppKit tests, the independent cold-launch harness and exact product-entitlement signature checks had passed locally. The AppKit tests exposed and fixed stale capture during a batched storage edit; synchronous IME/undo fixtures now create explicit undo groups. The PR must also pass its final full self-hosted suite, all 83 SIGKILL scenarios per Debug/Release configuration, both sandbox volume scenarios, Debug build and universal Release archive before merge. Exact final-head CI evidence belongs in the PR.

The preceding repository-maintenance CI run passed 124 Swift/AppKit/UI tests, 11 repository tests and the then-current 74 crash drills. Earlier main runs failed through UI interruption/input delays, retained in [#29](https://github.com/Orbitane-Limited/NoteHush/issues/29); this report does not close that reliability investigation. No timeout, assertion or retry policy was relaxed to obtain these results.

This is not a measurement of first editable frame, typing/render latency, tab switching, Find, large-file Open, font/wrap/printing, peak RSS, idle CPU, energy or worst-case lost-input interval. The M1/8 GB minimum reference machine, Intel/minimum-macOS runtime, VoiceOver, real IMEs and distribution signing remain unverified. Recovery-file/workspace/export size guards are allocation safeguards, not performance-qualified limits. No release or whole-app speed claim follows from this microbenchmark alone.
