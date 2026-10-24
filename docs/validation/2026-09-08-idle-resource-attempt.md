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

## Bounded activation observation after native CI resumed

At 07:40–07:41 UTC, a separate host-only diagnostic observed a **new empty UUID
workspace** using the unchanged optimized executable identified above. PR #47's
native tests and builds had finished; its artifact upload was still running.
This diagnostic collected no CPU/memory acceptance data and did not send keys,
read the clipboard, inspect another app or change the original failed fixtures.

LaunchServices requested activation with its documented default. The returned
NoteHush process was initially unfinished/inactive, active at observations 1–19,
and inactive at observations 20–30. One explicit `activate(options: [])` request
was accepted; all ten subsequent one-second observations reported active. Normal
termination and exact empty-buffer/selection/default-preference recovery passed.
The foreground change is now directly observed, but its origin remains
unattributed. Apple's [macOS activation notes](https://developer.apple.com/documentation/macos-release-notes/appkit-release-notes-for-macos-14)
explain that activation is a request, not a guaranteed state. This is not evidence
that a persistence defect or the old interruption cause has been fixed.

The diagnostic's first implementation constructed the expected app URL without
an explicit directory hint and failed identity comparison before observing it.
A separate scoped check with `.isDirectory` verified the exact returned URL/path
and stopped that newly launched process normally. The corrected diagnostic used
a new UUID. Both fresh empty workspaces and their checksummed recovery/blob data
were verified and retained. The production fixture harness already uses the
correct directory hint; no shipping or collector source changed for this check.
Private source, plans, all observations and failure evidence remain under the
root checkout's ignored `build/idle-activation-diagnostic/` directory.

PR #47 subsequently completed full CI and was merged as `94ad233`; its 62 native
AppKit/UI cases passed. The original idle attempt remains rejected, and a complete
60-second two-workload idle observation is still required. Continue unrelated
issue integration while preserving the collector's active-state and recovery
requirements.
