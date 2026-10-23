# Unattended UI automation startup failure

Observed 2026-09-08 UTC / 2026-09-09 PKT. Issue #29. The owner confirmed a new eight-hour exclusive Mac window at 22:04:56 UTC. The dedicated runner's `notehush` label was restored, and it acquired PR #65 CI run [34212827145](https://github.com/Orbitane-Limited/NoteHush/actions/runs/34212827145) for source `31c6980411d1f2769b13122cba69dc7ccff56622`.

The disk preflight, 45 repository tests, 85 core tests, all 166 crash drills, the full cold-launch harness and 34 AppKit tests passed. The UI runner failed to initialize, reporting `Timed out while enabling automation mode.` No UI test case executed. The job failed; its verification-artifact upload completed successfully. Later Debug/archive/performance stages were not reached. The complete failed result and source provenance are also retained privately in `build/validation-issue64-34212827145-failed` in the development checkout. No retry or passing UI result is claimed.

## Host observation and boundary

The read-only Apple command `/usr/bin/automationmodetool` reported that Automation Mode was disabled and administrator authentication was required to enable it. Its installed manual distinguishes this authentication prerequisite from whether mode is currently enabled. CoreGraphics reported a console login and completed login; the queried screen-lock key was absent, which is recorded as absent rather than a positive lock/unlock guarantee. No system window, authorization message, user note or input stream was inspected.

The runner service has `SessionCreate=true`, from its existing service configuration. This observation alone does not establish the cause of the timeout, and the service configuration was not changed. Likewise the new status observation does not retrospectively identify the historical UserNotificationCenter dialog, unexpected fixture bytes or every event delay. Earlier successful UI runs remain valid on their recorded conditions.

The owner was sent Apple's administrator command for unattended Automation Mode configuration. No authentication/accessibility policy, TCC database, security preference or signing permission was changed by the agent. Remaining jobs are temporarily held by removing only `notehush`; the current failed run was allowed to finish its artifact upload. This hold is for the known unattended-startup prerequisite, not expiration of the newly confirmed Mac window.

## Preflight correction

`check_ui_automation.py` invokes only the fixed Apple status command, without arguments, in the caller's service context. It accepts the complete two-line status format from the installed tool, rejects malformed/extra output, and bounds the command at five seconds. All command/read failures are static, private errors. It passes when mode is already enabled or the machine does not require authentication to enable it; otherwise it fails with an actionable owner setup message. The app, launch-performance and interaction-performance entry points check before creating fixtures and again before native execution after builds. Host-only idle collection and ordinary builds do not use XCTest and are unaffected.

Six offline tests cover all four status combinations, unexpected/partial output, nonzero exit/timeouts/read failures, private error handling, the precise read-only command and actual shell control flow. Before integrating the preflight, all three driver subcases proceeded into stubbed native preparation and returned its sentinel status 97 instead of the preflight failure. After integration, they stop before any fixture/build marker. The entire **64-test repository suite passes in 2.474 seconds**. The live preflight correctly returned failure for the unchanged host prerequisite without starting a native test.

The preceding draft's Swift builds and native observations are not relabeled as validation of this new shell change. Full final-head CI and the residual #29 input assessment remain required. The successful independent build/cold-launch checks do not replace the failed UI suite or establish App Store readiness.
