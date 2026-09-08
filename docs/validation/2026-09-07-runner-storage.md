# UI-runner termination and disk headroom

Issue [#48](https://github.com/Orbitane-Limited/NoteHush/issues/48), 2026-09-07, NoteHush 0.1.0 (1). Retained process diagnostics identify macOS cache reclamation as the cause of seven UI test-runner kills across two CI runs. The new preflight reports insufficient disk headroom before starting native validation; it does not suppress termination, alter entitlements or relax tests.

## Confirmed termination evidence

[PR #44 CI 34099345754](https://github.com/Orbitane-Limited/NoteHush/actions/runs/34099345754), head `754df992029e2b39f7dd7399fe5c59b7e67c1257`, reported five cases as `Test crashed with signal kill`. Each corresponding RunningBoard record explicitly names `pk.codehub.NoteHush.UITests.xctrunner`, code `0xBADDD15C`, and `CacheDeleteAppContainerCaches` requesting termination:

| UTC termination time | Interrupted case |
| --- | --- |
| 08:15:49.716952 | Native Find/Replace Unicode, case and independent undo |
| 08:16:38.678427 | Bookmark move/restart/Save renewal |
| 08:17:42.164552 | Conflict Reload/Undo, during teardown |
| 08:18:30.256895 | Deleted file Relink/Save As |
| 08:28:53.884035 | Pointer/keyboard reorder, during restart |

[PR #47 CI 34103461450](https://github.com/Orbitane-Limited/NoteHush/actions/runs/34103461450), head `2a56099641aceee5865fb14e34f8ef4525104f1c`, has the same termination records at **09:04:10.077970** and **09:04:36.348999 UTC**, for the bookmark and conflict cases. The completed native invocation reports **59 passes, two failures, zero skipped** across 61 cases. All 34 AppKit tests passed, including the new scrollbar regression; 28 repository tests, 85 core tests, 166 crash drills and cold launches also passed. The separate offline-volume case and later Debug/archive/performance-build stages were not reached.

Apple's [SIGKILL documentation](https://developer.apple.com/documentation/xcode/sigkill) defines `0xbaddd15c` as an operating-system termination to reclaim cache storage. This establishes the reason for these seven kills. It does not diagnose the three explicit one-minute timeouts in the first run, older capture/input interruptions or the unidentified system dialog tracked by #29. No unrelated app or system-dialog contents were inspected to obtain these records.

Raw evidence remains in root `build/validation-issue43-754df99-failed/` and `build/validation-issue46-2a56099-failed/`, including complete logs and `Lifecycle-66DAF050-9428-48CC-8062-E3F0A9B77CEF.xcresult` / `Lifecycle-C5BB301C-35E1-4537-AD6A-AA65BB6DB450.xcresult`. The former's exported diagnostics retain the historical termination records. Scoped extracts are `/tmp/notehush-issue43-owned-runner-kill-reasons.json` and `/tmp/notehush-issue46-current-runner-termination.json`; only relevant owned-runner termination records support this report. Initial archive queries without debug/info records did not reveal the cause; the later scoped query did. An initial sandboxed log read/report export failed, then the approved read completed. Failures were retained.

## Cleanup and policy

The host reported about 14 GiB available and 97% capacity used. A bounded cleanup removed 53 ignored compiler-cache directories from inactive NoteHush checkouts, reclaiming approximately **3.1 GiB** (13.274 to 16.419 GiB free at the before/after observations). It retained binaries, logs/results/traces/archives and all recovery evidence; the active CI checkout and unrelated storage were untouched. The local cleanup manifest is `build/host-build-cache-cleanup-2026-09-07.json`.

At **09:15:10 UTC**, the new preflight recorded total capacity **494,384,795,648 bytes**, available **15,648,395,264 bytes**, and required **49,438,479,565 bytes** for both workspace and temporary filesystems. Available space can change while other work runs. The gate correctly exited 1 and retained its report. On this filesystem the policy requires approximately **46.04 GiB free**; additional operator cleanup is required before running native validation again.

The policy requires the greater of 20 GiB and 10% of filesystem capacity, rounded up to a whole byte. This is an engineering margin, not an Apple-specified purge threshold. It does not count potentially reclaimable space, automatically delete files or guarantee that capacity remains sufficient afterward. A read or report-write failure stops work. Each invocation retains a separate JSON report without paths or user/device identifiers. CI/full checks, standalone native test/archive/performance-build scripts and measurement/profile entry points enforce the gate; measurement/profile and app tests check again after building.

## Validation and remaining work

All **34 repository tests pass**, including six new storage regressions. Configuration checks, shell syntax and diff checks pass. The real low-space preflight fails as intended. Tests verify strict boundaries, proportional capacity, invalid/unreadable values, both volume roles, preservation of multiple reports, failed report writes and downstream-command exclusion for every native shell entry point. No test assertion, timeout or screenshot requirement changed.

Full CI is still required after the operator restores headroom. PR #47 and draft #44 remain gated on complete native checks, and optimized combined launch/interaction measurements remain pending. No performance samples were collected during this disk-pressure investigation. The interaction script from unmerged #43 must receive the same direct/post-build guard when integrating this change. The broader #29, minimum-hardware and distribution-signing gates remain open; no App Store readiness is claimed.
