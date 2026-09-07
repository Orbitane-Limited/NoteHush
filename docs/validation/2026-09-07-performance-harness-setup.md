# Performance fixture setup validation

Date: 2026-09-07, approximately 00:29 UTC. Issue #35 remains open. This was a functional isolation/setup check, not a performance benchmark or product-budget acceptance.

Checkout: `79da64ad570136a9a03a2cafdd7a283f95f25531`. Host helper includes directory-URL correction `e21b3ac`. The existing optimized app executable's SHA-256 was `6532c3c7d655ed0fbd8f28e20f4f1a979a19a5abea8ece9f0242712307e4d6f6`. The app still used schema-5 recovery; a final measured baseline must rebuild with the merged #31 migration.

`verify_test_app.py --configuration ReleasePerformance` passed for the separate `pk.codehub.NoteHush.PerformanceTesting` bundle and exactly the four product sandbox entitlements. The host helper compiled successfully. The Xcode build task records for this app also specify Swift `-O` and whole-module optimization for the linked `NoteHushCore` module.

`PerformanceFixtureHarness prepare` passed its missing/invalid UUID rejection checks, launched and normally terminated three separate generated workspaces, and seeded the empty/5 MiB/30 MiB fixtures. `cleanup` then passed and removed their generated directories and manifest. Normal recovery storage was never selected. Setup ran after main CI's complete validation step, including its offline-volume UI case, had finished; only artifact upload remained, and recovery PR CI was still queued. No timing samples were collected.

The preceding setup attempt had failed with `launchFailed`. A focused Foundation check showed equal filesystem paths but unequal URLs when only one carried the app directory's trailing slash. The helper now creates the input URL with an explicit directory hint, preserving the exact bundle-location guard, and reports a wrong-build mismatch separately. The corrected functional run passed. No entitlement, identity requirement or timeout was relaxed.

Local log: `/tmp/notehush-issue35-fixture-prepare-fixed.log`. The complete XCTest measurement run, sample extraction, all-buffer post-measurement verification, app-only Instruments run, and final regression CI remain unverified at this point. This setup result does not establish app speed, GUI input exclusivity, minimum-hardware behavior or App Store readiness.

## First metric-wiring attempt

At 00:40 UTC, with both CI runs complete and the runner idle, a focused empty-workspace measurement case used schema-6 checkout `5ac72826ea12930e8d5629bc451ae4136a5d3752` (clean) and app SHA-256 `85c442e7d8669b0b04a77f3df2d5874bf1051cf0ec6115de1f562f912700d170`. The required build/signature checks and generated fixture setup passed. This was harness diagnosis before #31 merged, not the final baseline.

The first iteration failed the `editor.isEnabled` assertion. A separate in-memory AppKit check showed a fresh `NSTextView` with `isEditable == true` returning `false` from `isAccessibilityEnabled()`, also returning false after making it read-only. That accessibility flag cannot serve as this harness's editability oracle. The run also waited for termination after the driver's `NSRunningApplication.terminate()` request, and the following launch reported terminating the previous process. No claim is made about why that request did not produce the expected XCTest state.

The identified test invocation was interrupted rather than collecting more invalid samples. Xcode exited 73 during cancellation/finalization; owned-fixture cleanup passed and removed the manifest. Preserve `build/logs/PerformanceWiring-DD56D2F7-E2E1-45F6-A9A3-F3A0EE334C93.xcresult`, its environment JSON and `/tmp/notehush-issue35-launch-wiring.log` as failed-run evidence. No timing results from this attempt are accepted.

The driver now verifies a generated keyboard edit at the restored caret, Undo back to the exact original digest, and Cmd+Q termination through both XCTest state and the identified process. Every iteration also requires the app to be stopped before launch. All these operations remain outside the reported launch/readiness intervals. The updated optimized test build and exact sandbox signature passed; runtime validation of this correction remains pending. No functional CI assertion, timeout or entitlement was changed.

## Corrected editability and Quit check

With CI idle, the corrected empty-workspace case passed in 81.001 seconds on checkout `bcc36a0`, finishing at 00:55 UTC. Every keyboard edit, Undo digest, selected tab, stopped-process precondition and Cmd+Q termination check passed. The app's strict sandbox signature and generated-fixture cleanup also passed. This precedes the final merged-source baseline and exercises only the empty scenario.

`PerformanceWiring-A17B07F5-B098-41BD-A92D-41AEC14B758F.xcresult` and its exported `-raw.json`/`-environment.json` are retained in `build/logs`; the text log is `/tmp/notehush-issue35-launch-wiring-fixed.log`. Actual export contains one test run and exactly 20 finite, nonnegative samples in seconds for each of `ProcessToEditorReady` and `ApplicationFirstFramePresentationResponsive`. The log records 21 launches, matching the extra first warm-up documented by the installed `XCTMeasureOptions.h`. No further sample removal is performed.

The log also contains nine `Unable to monitor event loop` messages during teardown. Following the installed XCTest manual-stop API, the driver now calls `stopMeasuring()` before fixture assertions and Quit so collection ends while the measured process is alive. This boundary adjustment still needs runtime validation in the complete three-scenario run; the earlier result and diagnostics remain preserved. No speed or minimum-hardware claim is made from this wiring check.
