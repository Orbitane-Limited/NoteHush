# Native file-access test setup

Issue [#37](https://github.com/Orbitane-Limited/NoteHush/issues/37), on main base `ce47151b6972c7539589f52662490cce37aa9bb0`. This changes test setup only; it does not establish app-performance budgets or resolve every input interruption in [#29](https://github.com/Orbitane-Limited/NoteHush/issues/29).

## Final implementation and focused result

The two long relink/Save As and repeated-overwrite cases use the existing warm Finder/LaunchServices opening path for the initial generated source. XCTest supplies the UUID at launch; setup validates the isolated bundle/marker, exact executable location and existing process ID, disables application substitution, and checks selection plus the original fixture text. The native relink, conflict-review and Save As actions and all previous assertions remain. Other file-access cases and the dedicated panel tests still use the initial Open panel.

On 2026-09-07 at 00:02 UTC, both cases passed with `DebugUITesting`, macOS 26.6.2 (25G83), Xcode 26.6 (17F113), arm64 on the shared M4 Pro Mac. No CI GUI test was active. Other human/project input exclusivity was not confirmed. The app signature was re-applied and verified against the exact four product entitlements before and after the run.

| Case | Result | Total XCTest duration |
| --- | --- | --- |
| Deleted file → relink → conflict → Save As, preserving both external files | Passed | 39.756 s |
| Reject a disk edit after overwrite review, then require and complete a second review | Passed | 14.583 s |

Each case verified its initially selected text at approximately 3.8 seconds. The unchanged functional case limit is 60 seconds; expectations retain their existing timeouts. These are individual test execution observations, not a controlled benchmark or proof that the shared host is free of input delays.

Command: `xcodebuild test-without-building` with scheme `NoteHush`, configuration `DebugUITesting`, destination `platform=macOS,arch=arm64`, parallel testing disabled, the existing 30-second default/60-second maximum allowances, and only those two cases. Local evidence: `build/logs/FileAccess-FinderSetup.xcresult`; full console log `/tmp/notehush-issue37-finder-focused.log`. The tested `FileAccessTests.swift` SHA-256 is `1edc400bef0cf02d5055e95246949d7244fbe3f68f9be590c0d75c59ab03af69`. Compilation, strict Swift formatting, configuration/link checks and signature verification passed. Complete regression CI remains pending.

## Earlier failures retained

Both attempts of [recovery CI 34065905345](https://github.com/Orbitane-Limited/NoteHush/actions/runs/34065905345) on `68be0346ab301ad0914e58a67b7baccf07fa6624` failed the existing relink case at 60 seconds. Each completed result reported 57 passing AppKit/UI tests and one failure; 85 core tests and 166 crash drills passed earlier. Offline-volume and build/archive stages were not reached. Full copies are retained locally under `build/validation-issue31-ci-failure/logs` and `build/validation-issue31-ci-attempt2/logs` in the root checkout. GitHub retained both validation artifacts. No further unchanged-commit retry was requested.

A local alias experiment shortened a generated fixture directory from 139 to 27 bytes. It exposed two setup bugs (Foundation's `/private/tmp` normalization and an existing run directory after XCTest restarted), which were corrected during the experiment. Bookmark movement passed in 42.048 seconds; repeated overwrite later passed in 37.130 seconds and generated interrupted-case evidence survived unchanged. Relink still timed out. The final change therefore uses the already-supported Finder setup and includes no alias/host-fixture code. Experiment sources/patches and failed result bundles remain under the issue worktree's ignored `build/experiments/file-access-alias` and `build/logs` directories. Failures are not counted as successful validation.

#29 remains open for unexplained native-input stalls, the earlier unidentified system dialog and exclusive-input protocol. No system-app inspection, dialog dismissal, manual screenshot capture or interruption of another project was performed for this work. Signing, minimum-hardware/OS, accessibility and App Store release gates remain open.
