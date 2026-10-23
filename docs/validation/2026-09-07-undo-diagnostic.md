# Isolated native Undo diagnostic

Date: 2026-09-07. Issue #29. Candidate branch: `issue-29/undo-diagnostics`, starting from main `2c786fac01a59e548475c20f985050c0a430e992`. This is diagnostic preparation, not a confirmed fix for the retained native Find failure. No native diagnostic result or full passing CI is claimed here.

The [2026-09-08 supplement](2026-09-08-input-diagnostic.md) adds bounded event-source metadata after a later generated switching fixture changed unexpectedly. The original preparation results below refer to the earlier probe.

## Failure boundary to distinguish

The [combined CI](https://github.com/Orbitane-Limited/NoteHush/actions/runs/34136196487) failed the original native Find case after a single replacement, Done and Cmd+Z. Its synthesized event targets the identified app, but the original text expectation fails. Both retained recovery generations contain the exact single-replacement fixture with valid checksums/encoding. A later unchanged focused case passed. See the [immutable combined report](https://github.com/Orbitane-Limited/NoteHush/blob/f18976483642dd8da8dae1bc28d1636e00ce7aae/docs/validation/2026-09-07-m5-integration.md).

Record whether the known Cmd+Z reaches the app's local event monitor, whether the selected editor is first responder, whether its UndoManager emits will/did notifications, and which known fixture state the in-memory editor contains. This distinguishes failed delivery, another responder handling Undo, incorrect buffer state and a possible XCTest value-observation failure. A local event record alone does not prove where the responder chain sends the command. A next-main-queue-turn observation does not establish that nested AppKit processing or display presentation has completed.

## Isolation and evidence

- Compile only under `DEBUG && NOTEHUSH_REQUIRE_TEST_WORKSPACE`. Normal Debug, Release and ReleasePerformance contain no probe.
- Activate only with the exact `pk.codehub.NoteHush.UITesting` bundle, a valid matching UUID in the existing `UITests` namespace and `NOTEHUSH_UNDO_DIAGNOSTICS=1`.
- Return every event unchanged. Observe only process-local notifications and state on the identified workspace. Use no global event monitor, event tap, AX query, activation, global setting change or system-dialog inspection.
- Records contain sequence/elapsed time, fixed event names, Boolean state and a fixed fixture classification. Only text of at most 128 UTF-16 units is compared with the published Find-test oracle; other text becomes `other`. No text, digest of unexpected input, path, bookmark or clipboard contents are emitted.
- Keep a maximum of 256 observations. Write off the main actor, in observation order, to a new `undo-diagnostic-<UUID>.jsonl` with exclusive creation and mode 0600 inside the generated workspace. Never truncate older evidence. Normal Quit drains/synchronizes/closes the writer; forced termination can leave missing or partial records. Write failures emit only a fixed failure label, never an Error description.
- `limitReached`, missing shutdown and the absence of a key/Undo observation are limitations to interpret against the complete test result. None is a passing-test designation.

## Bounded execution

1. Confirm an awake/unlocked exclusive-input window, idle self-hosted runner, no competing owned native process and sufficient disk headroom. Build/re-sign the isolated app and verify exact product entitlements before and after testing.
2. Clone the generated `.xctestrun` beside its original file so `__TESTROOT__` resolves identically. Add only `NOTEHUSH_UNDO_DIAGNOSTICS=1` to the UI test host's `EnvironmentVariables`. The test forwards that opt-in to its existing UUID-isolated app and attaches only that generated workspace identifier.
3. First run the unchanged `EditingTests/testNativeFindReplaceUnicodeCaseAndIndependentUndo()` once to validate the instrumentation itself. Use a fresh result bundle, disabled parallel testing and the existing 30-second default/60-second maximum execution allowances.
4. Extract only the attachment named `Isolated Undo diagnostic workspace`, validate its UUID, and inspect only that workspace's generated diagnostic files. Pass each explicitly selected file to `scripts/summarize_undo_diagnostic.py`; retain raw results privately. Do not discover or read normal recovery workspaces.
5. If further reproduction is necessary, declare a fixed iteration count before starting and retain every outcome. Xcode's `-test-iterations` can repeat a fixed count; do not use retry-on-failure or run-until-failure options. Instrumented diagnostic timings must not replace the uninstrumented performance protocol.
6. Choose an implementation correction only after evidence identifies the boundary. Keep failed CI visible and preserve all current assertions, fixture inputs, timeouts, privacy and recovery behavior.

The installed Xcode `xcodebuild.xctestrun(5)` documents the test-host `EnvironmentVariables` and `__TESTROOT__` behavior. Public API references: [local event monitoring](https://developer.apple.com/documentation/appkit/nsevent/addlocalmonitorforevents(matching:handler:)), [UndoManager](https://developer.apple.com/documentation/foundation/undomanager).

## Completed preparation checks

- 36 repository automation tests pass, including diagnostic exclusion from a separate Debug code library, unknown data/invalid timeline rejection and explicit incomplete-trace limitations.
- All 85 core tests pass with code coverage enabled.
- Strict Swift formatting, configuration/relative links, shell syntax and diff checks pass.
- `DebugUITesting` build-for-testing and exact product sandbox signature verification pass.
- Normal Debug build, unsigned universal Release archive and optimized ReleasePerformance build pass. The diagnostic is present in the isolated test code and absent from all three other configurations, including adjacent `.dylib` code artifacts. The original launcher-only presence assertion correctly failed to prove inclusion; checking the actual Debug code library resolved that incomplete inspection without removing an exclusion assertion.
- The Swift 6 build initially rejected returning non-Sendable `NSEvent` through `MainActor.assumeIsolated`. The assertion now returns only Void; the original event is returned directly from the local-monitor handler.

Full native validation, final-source CI, the original failure's cause and the other #29 findings remain open. Build logs and the complete app-code artifact hash manifest are private under this checkout's `build/logs/undo-diagnostic-final-*` files. No independent review, performance acceptance or App Store readiness is claimed.
