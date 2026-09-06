# M5 lifecycle and failure validation

Issue: [#11](https://github.com/Orbitane-Limited/NoteHush/issues/11). Branch: `issue-11/lifecycle-fault-tests`, based on main `92c3f66f1a6f69ce29ba6c3307911b33af0f5504`. Version: 0.1.0 (1). These are local implementation results; full PR CI and remaining release gates are not yet complete.

Environment: Apple silicon Mac, Xcode 26.6, Apple Swift 6.3.3, macOS 26.6.2. The app targets macOS 14; this host does not establish minimum-OS or Intel runtime support.

## Defects found and regression evidence

- The continuous-input executable crashed before its first checkpoint acknowledgment, with `swift_task_dealloc` / `freed pointer was not the last allocation` at `CheckpointCoordinator.timer`. Replacing only the sleep API did not fix it. Keeping the real sleep inside the timer task and making the injected sleeper optional did; the harness still exercises cancellation and `Task.sleep(for:)` from the linked client. Both Debug and Release now pass. [Swift issue 86204](https://github.com/swiftlang/swift/issues/86204) reports a similar symptom, but an identical compiler cause has not been established.
- A deterministic storage test first failed because an identical retry returned `unchanged` after the previous attempt renamed the primary but failed before directory synchronization. The store now retries that synchronization before acknowledging success. Continued synchronization failure stays an error, leaves both generations intact, and a healthy retry succeeds.
- A Settings control-order test first failed for both Appearance and Zoom: committing a size field reset a popup selection before its action arrived. Local preference publication now updates the relevant controls without rebuilding unrelated menus through the workspace callback. Both choices and the size survive that sequence. This reproduces a concrete defect consistent with the earlier main CI failure; it does not prove that run's exact native event ordering.

## Local checks

| Check | Result |
| --- | --- |
| `swift test` | 67 tests passed |
| `python3 scripts/test_crash_recovery.py` | 37 Debug SIGKILL drills passed |
| `python3 scripts/test_crash_recovery.py --configuration release` | 37 Release SIGKILL drills passed |
| `NoteHushAppTests` in DebugUITesting | 29 tests passed, including all new recovery/Settings cases |
| `PreferencesUITests` in DebugUITesting | 6 passed, 1 failed with a system UI interruption; not a passing suite |
| `swift run ColdLaunchHarness build/UITestDerivedData/Build/Products/DebugUITesting/NoteHush.app` | Missing/invalid IDs rejected; cold file event, dirty recovery and normal restart passed |
| Swift strict formatting, configuration and relative links | Passed |
| Ordinary unsigned Debug build | Passed |
| `bash scripts/archive.sh` | Unsigned Release archive passed configuration and arm64/x86_64 checks |

A signing audit found that build-for-testing injected broad read access and automation exceptions into the test app. The script now re-signs only that app with the four declared product entitlements and requires exact equality before/after UI runs. Cold LaunchServices checks passed again with this narrower signature. The earlier focused UI run used the injected signature, so it does not verify the tighter sandbox; the complete suite must run again. The XCTest driver remains a separate automation process. The re-signed test app has only App Sandbox, user-selected read/write, app-scoped bookmark and printing entitlements. It uses `pk.codehub.NoteHush.UITesting`; development and distribution identifiers remain separate. The test-only workspace requirement is disabled in the Release archive.

## Test scope

Each build configuration runs six write timings, three continuous-input interruptions and 28 deterministic filesystem phases. The latter stop after temporary write, file flush, atomic rename and directory flush during first publication, later publication and history cleanup. A separate oracle checks complete Unicode text, tab order/selection, file metadata, closed history, preferences and geometry; source file bytes must remain intact. A missing phase, early process exit or non-SIGKILL termination fails. These tests do not simulate loss of hardware write caches or certify the 500 ms lost-input performance budget.

The cold-launch driver only accepts the separately identified test app. It first checks the compiled guard with missing/invalid IDs, then supplies a generated UUID through the host LaunchServices API. The dirty-recovery scenario initially selects another tab, so selecting the requested named tab proves the file event ran. Each restart must create a later checkpoint. Observation reads the atomically replaced primary without competing for the app's writer lock. Cleanup touches only the driver's UUID fixtures. A signed Finder installation is still a distribution gate. API contract checked against the installed SDK and [Apple OpenConfiguration.environment](https://developer.apple.com/documentation/appkit/nsworkspace/openconfiguration/environment).

AppKit fault cases verify editable drafts and unchanged external UTF-16 bytes after storage failure, visible nonmodal warnings, successful Retry, persistent fallback warnings, preserved damaged evidence, and read-only behavior through Retry/Quit for corruption and future schemas in either slot. Existing schema migration fixtures remain required.

## UI interruption and open gates

[Post-merge main CI 34057284879](https://github.com/Orbitane-Limited/NoteHush/actions/runs/34057284879) failed the Appearance persistence expectation. Its Settings-only screenshot already showed System before Quit, so that run did not demonstrate a persistence loss.

The new focused local UI run (`Test-NoteHush-2026.09.07_01-47-36-+0500.xcresult`) passed Print/Page Setup cancellation followed by red-window close, Quit with each sheet open, keyboard font selection and Zoom/appearance shortcuts. The full Settings case encountered a `com.apple.UserNotificationCenter` dialog from its first typing action. XCTest later reported a disabled application/window and no keyboard focus in the font-size field. The dialog's message is unverified; Computer Use refused access to that system app. No alternate tool was used to inspect or dismiss it. This failure is retained, with no relaxed assertions or increased time allowance.

The full 124-test suite (67 core, 29 AppKit, 28 UI), self-hosted PR CI, and required volume scenarios must pass on the final change before merge. The older large-Find and file-panel delivery delays remain unexplained; passing retries do not establish their cause. Physical printer behavior, cold system print-service startup, production signing/TestFlight, manual accessibility/IME, minimum OS and Intel runtime remain unverified release gates under M5/M6. No production release or App Store readiness is claimed.
