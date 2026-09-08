# Idle-resource attempt — 2026-09-08 UTC

The first native #56 collection used clean integration source
`300f846c7edf309f42dc9a0ba53fd41b5da90b2d`, engineering version 0.1.0 (1),
and optimized sandboxed binary SHA-256
`a8f394cd2fa802b4f04a4c82fa45bde6c64fb290ad8e5fad086bfd9d9897d06f`.
The required optimized build, host build, provenance and exact sandbox checks
passed. This Mac has 24 GiB memory and 12 logical CPUs; macOS 26.6.2, Xcode 26.6,
AC power, low-power mode off and nominal initial thermal state were recorded.
The operator had a ten-hour exclusive-use window; no input was generated.

**No baseline was accepted.** After the declared 30-second settling interval,
the first empty-workspace counter read succeeded, but `applicationActive` was
false. The existing assertion stopped the run immediately. Only a header and
one sample exist; no finish footer, second sample, 60-second interval or five-MiB
measurement exists. Both generated fixtures, the partial recording and provenance
remain in the integration checkout's ignored directory
`build/logs/Idle-F59C1DBB-B8C6-45CF-BA46-94921EFF51EB/`.

The identified app stopped. A separate read-only check validated both complete
sets of generated buffer digests and blob checksums, text byte/UTF-16 counts,
tab order, active tab and selections. The empty workspace had advanced from
revision 3 to 6; the unlaunched five-MiB fixture remained at revision 3. Their
recorded scroll anchors/offsets matched the seeds. The exact product sandbox
signature still passed afterward. This recovery inspection does not turn the
incomplete measurement into a pass.

The launcher already requests foreground activation by default. Apple's
[OpenConfiguration.activates documentation](https://developer.apple.com/documentation/appkit/nsworkspace/openconfiguration/activates)
and the installed SDK both specify that default. Setting the same default again
would not explain this outcome. No other app or authorization dialog was
inspected, no focus requirement was removed, and the failed fixture was not reset
or relaunched. The cause of the inactive app remains unresolved.

The host originally reported only `fixtureOperationFailed` because its top-level
handler did not recognize idle-specific errors. A follow-up exposes only the idle
enum's fixed string codes, such as `inactiveApp`, keeping arbitrary errors private.
A deliberately wrong fixture set reproduced the generic error before the change;
the rebuilt host reports `wrongFixtureSet` with exit 1 before opening any workspace
or launching an app. All **37 standalone repository tests**, strict Swift formatting,
configuration/link checks and the Release host build pass. Sampling, workload,
timeouts, recovery assertions and shipping code are unchanged. Full native
collection, CPU/RSS budgets, energy and minimum-hardware acceptance remain open.


A separate headless probe checked the run-loop-cache hypothesis from Apple's
[NSRunningApplication documentation](https://developer.apple.com/documentation/appkit/nsrunningapplication).
With ten 100 ms suspensions, the same async-main entry style processed ten main
run-loop turns in common modes and stayed on the main OS thread; an explicit
run-loop entry processed eleven. This small experiment did not launch an app or
inspect other processes. It provides no evidence for replacing the collector's
entry point and does not explain the inactive sample. Its source and measured
counts are retained under the repository's ignored `build/runloop-diagnostic/`.
