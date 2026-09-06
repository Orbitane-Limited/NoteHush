# Schema-5 recovery performance baseline

Recorded 2026-09-07 Asia/Karachi (JSON completion timestamp 2026-09-06T22:05:14Z). Issue [#30](https://github.com/Orbitane-Limited/NoteHush/issues/30) supplies the baseline for [#12](https://github.com/Orbitane-Limited/NoteHush/issues/12) and the storage migration in [#31](https://github.com/Orbitane-Limited/NoteHush/issues/31).

## Build and conditions

- Benchmark commit: `4bc08d839f13eae32f84664e91f9342be2bef1f3`. Recovery/app code is unchanged from merged main `1ec7d887181560663ea0b8842443b4e24b5856d0`; storage schema 5, app version 0.1.0 (1).
- Apple M4 Pro, Mac16,8, 24 GiB memory, 12 logical processors; macOS 26.6.2 (25G83). This is not the M1/8 GB minimum reference machine.
- Xcode 26.6 (17F113), Swift 6.3.3; native arm64 SwiftPM Release build, no debugger.
- AC connected, Low Power Mode off. CI had completed and the NoteHush runner API reported online/idle before execution. Other projects were not stopped; these timings remain informational on a shared Mac. Thermal state was not recorded.
- Newly generated private temporary directories, unique tab prefixes, alternating ASCII and Arabic/combining-mark/emoji content with CRLF. Each tab begins at exactly 256 KiB. No app is launched, and normal recovery storage is never accessed.
- Filesystem caches are warm after the initial untimed commit. Each timed restore creates a new RecoveryStore, without an existing in-process store cache. Checkpoints reuse one store. Selection changes affect the first tab; one-tab edits alternate between its ASCII and Unicode neighbor, adding one ASCII byte per sample.
- Every sample is followed by an untimed canonical-byte recovery comparison. Counters reset before the next sample. Timing includes the RecoveryStore call and its I/O instrumentation, excluding fixture creation, content mutation and correctness verification.

Commands executed:

```sh
swift build -c release --product RecoveryBenchmark
.build/release/RecoveryBenchmark > build/recovery-baseline-schema5.json
```

The executed binary SHA-256 is `689a976d00cc58197284ef546c6af96d9451556ffcd6fdbd25188adc48dfeb0a`. The benchmark exits unsuccessfully on a recovery mismatch or I/O error and deletes only its generated fixture root.

## Results

Twenty samples per operation and workspace. Median is the average of the two central samples; p95 is nearest rank, the nineteenth sorted sample. Raw values and software/hardware metadata are retained in [the JSON report](2026-09-07-recovery-schema5.json). An independent Python check verified all 20-value arrays, nonnegative finite measurements, medians, p95 values and expected schema-5 write counts.

| Workspace | Operation | Median ms | p95 ms | Median read MiB | Median write MiB |
| --- | --- | ---: | ---: | ---: | ---: |
| 20 open / 5 MiB | restore | 113.55 | 146.28 | 15.006 | 0.000 |
| 20 open / 5 MiB | selection-only | 147.78 | 153.92 | 15.006 | 15.006 |
| 20 open / 5 MiB | one-tab-edit | 147.39 | 181.83 | 15.006 | 15.006 |
| 100 open + 20 closed / 30 MiB | restore | 655.43 | 671.54 | 90.036 | 0.000 |
| 100 open + 20 closed / 30 MiB | selection-only | 886.98 | 1021.87 | 90.036 | 90.036 |
| 100 open + 20 closed / 30 MiB | one-tab-edit | 903.56 | 950.56 | 90.036 | 90.036 |

Reads and writes are logical bytes crossing RecoveryFiles, not physical SSD traffic. Restore writes zero files; every measured checkpoint writes two complete generations. Encoded envelopes are larger than plain text, so a 30 MiB workspace reads and rewrites about 90 MiB even when only its selection changes. One-tab edits have nearly the same cost as metadata-only checkpoints. This is direct evidence for reducing unchanged-text work with immutable blobs and small manifests; it is not evidence that the app is already fast.

## Validation and remaining gates

The Release benchmark completed all 120 measured operations and their recovery comparisons. Configuration/relative-link checks, strict Swift formatting and 67 core tests passed locally. The benchmark PR records the final self-hosted checks and artifacts for its complete head; those results must pass before merge.

The preceding [main CI run 34062192313](https://github.com/Orbitane-Limited/NoteHush/actions/runs/34062192313) failed the existing relink/Save As UI test at its unchanged 60-second limit. Earlier pre-merge CI for #28 passed all 124 tests and 74 crash drills. The main failure and event-synthesis delays remain tracked in [#29](https://github.com/Orbitane-Limited/NoteHush/issues/29); this benchmark neither fixes nor conceals them. Its measurements started after that failed run completed. No retry or time allowance change was made to obtain these benchmark results.

This report does not measure first editable frame, typing/render latency, tab switching, native Find, large-file Open, font/wrap/zoom/printing responsiveness, RSS, idle CPU, energy, or the actual lost-input interval under interruption. It provides no minimum-macOS/Intel/M1 result. Whole-app budgets and Instruments evidence stay open in #12; accessibility/platform checks stay in #13 and signing/TestFlight remains in #14. No production release or performance marketing claim follows from this baseline.
