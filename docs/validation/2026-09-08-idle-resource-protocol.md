# Settled CPU and memory measurement protocol

Date: 2026-09-08. Issue #56, child of #12. Starting source: main `2c786fac01a59e548475c20f985050c0a430e992`. This is host-only measurement preparation; no NoteHush idle result or release budget pass is claimed.

## Scope and ownership

`PerformanceFixtureHarness prepare-idle` uses the existing optimized, UUID-isolated app to generate exactly two workloads: one empty tab and 20 tabs of 256 KiB each, totaling 5 MiB with alternating ASCII and Arabic/combining-mark/emoji CRLF. It preserves the existing launch-guard checks and warm filesystem-cache conditions. No app runtime source, build entitlement, recovery format or functional timeout changes.

The `idle` command requires those exact fixture names and the existing manifest's application URL, bundle markers and unique UUIDs. Before each case, it refuses an already-running performance app. Only the process returned by the exact LaunchServices request is eligible for counters or termination, after its bundle URL and identifier match. Each reading checks that process again, plus its unchanged kernel start identity. No task port, debugger, global process list, unrelated app, user workspace, note text, path, bookmark or clipboard data is collected by the sampler. The existing private fixture/provenance manifests contain only the generated workspace/build references.

## Fixed collection window

Allow 30 seconds after LaunchServices returns, checking the owned app remains alive every second. This is a fixed settling interval, not proof that all deferred work has ended. Any continued CPU work stays in the recording.

Collect 61 observations with at least one second between each read's end and the next read's start. This guarantees at least 60 elapsed seconds across the observation window rather than treating 60 point samples as 60 intervals. Record monotonic bounds before/after every public `proc_pid_rusage(..., RUSAGE_INFO_V0, ...)` call, both raw CPU counters, resident bytes, physical-footprint bytes and whether the identified app remains active. Inactivity, a failed read, process exit/reuse or any later verification error fails the run. There is no interactive input or AX query in this collector. A confirmed exclusive window is still required because a competing input can change the fixture or foreground conditions.

The raw CPU fields are **Mach clock ticks**. Preserve the host's `mach_timebase_info` numerator and denominator in each header. Convert the delta once: `nanoseconds = deltaTicks × numerator / denominator`. Divide total user-plus-system nanoseconds by actual elapsed nanoseconds and multiply by 100; 100% means one occupied logical core. Do not divide by the machine's core count. The summary also reports the range implied by the two counter-read bounds and every interval's CPU percentage.

RSS and physical footprint are different counters, reported separately in bytes with minimum, median, nearest-rank p95, maximum and final value. These are observations within one process/window per workload, not 61 independent launches. Keep every outlier and raw sample. No physical energy, battery-drain, display scan-out or complete startup measurement is inferred.

## Completion and evidence

Request normal app termination, require it to finish within the existing 20-second host bound, then verify all open/closed buffer digests, order and selected tab. Compare every open-tab UTF-16 selection, normalized default preferences and logical viewport/offset with the seed; zero/nil initial scroll representation is normalized, with the existing one-point viewport tolerance. Only then append the verified finish record and flush/close the private evidence file.

Raw files use exclusive creation, no-follow protection and mode 0600. The operator script creates a unique private run directory and never automatically deletes its fixtures, including after collection failure. Partial or missing files remain available. A failure stops downstream summary publication; the collector may force only its own identified process as a failed-run cleanup after ordinary termination has failed. This never counts as normal termination. Inspect retained outcomes before explicitly cleaning a generated manifest with the existing helper. The existing preparation helper's failure cleanup is separate from completed fixture collection.

The strict Python summary requires both workloads once, identical clock provenance, exact header units/fields, 61 ordered samples and the verified finish. It rejects duplicate JSON keys, unrecognized payload fields, noninteger/negative/overflow counters, shortened/nonmonotonic intervals, CPU resets, missing cases, symlinks, nonregular files, oversized artifacts and partial records. Unknown data is not printed in errors. A valid summary still does not certify product performance or signing.

## Operator command

First establish exclusive keyboard/mouse access, idle CI, sufficient disk space, AC power and fixed display conditions. Resolve the outstanding #29 input conditions before collection. The disk-headroom protection in #48 must be included in the final integrated build script before release validation. No automatic native idle job is added to normal CI.

```sh
NOTEHUSH_EXCLUSIVE_INPUT=1 bash scripts/measure_idle_resources.sh
```

The command builds the optimized isolated app and Release host, creates fixtures, records source/binary/hardware/toolchain/power/thermal/display provenance and verifies exact sandbox signatures before/after collection. It also rejects dirty or changed source and a changed executable before producing the summary. Artifacts remain in `build/logs/Idle-<UUID>/`. Existing fixture cleanup is explicit and must only receive that generated manifest after the owned app has stopped. Do not automatically retry a failed attempt or aggregate unrelated run directories.

The unchanged PRD targets are 80 MiB empty / 150 MiB for 20 tabs and less than 1% average CPU over 60 seconds. Report observed RSS and footprint separately when assessing those targets; do not silently choose whichever counter passes. This protocol leaves physical energy, large-file/display/print/history workloads, 20-run latency measurements and M1/8 GiB acceptance open.

## API and preparation evidence

The installed SDK exports `proc_pid_rusage` from macOS 10.9 and the required V0 fields. Apple's pinned [resource implementation](https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/osfmk/kern/bsd_kern.c), [task clock accounting](https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/osfmk/kern/task.c) and [userspace wrapper](https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/libsyscall/wrappers/libproc/libproc.c) establish the tick-valued CPU counters and distinct memory fields. The wrapper forwards the counters without converting them to nanoseconds.

A newly created, headless calibration process sampled only itself and compared converted resource deltas against `CLOCK_PROCESS_CPUTIME_ID` across generated CPU work. On this M4 Pro, the timebase was 125/3; converted resource CPU was 199,927,958 ns versus 199,927,000 ns from the independent process clock. This checks conversion and C interoperability on the available host, not NoteHush CPU use or other hardware. The calibration source and log remain private under `build/`.

All 37 repository tests pass, including clock conversion, retained outliers, incomplete/invalid evidence and operator/clean-source guards protected from launching a build during tests. All 85 core tests pass with coverage. Debug and Release host builds, strict Swift formatting, configuration/relative-link validation, shell syntax and diff checks pass. The optimized isolated app's build-for-testing passes with exactly the product sandbox entitlements. Private logs are retained under `build/logs/idle-*`.

The real two-workload native run, full final-head CI, independent review and all release acceptance remain pending. No NoteHush app was launched by the preparation checks. Normal app runtime sources and entitlements are unchanged; the self-process calibration is separate from product acceptance.
