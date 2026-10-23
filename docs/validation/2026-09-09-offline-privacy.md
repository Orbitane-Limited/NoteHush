# Offline privacy window

Issue #68; baseline `bb49b49c5cb3ead161f774d087d9fd26481f73e1`, tested 2026-09-09 local time with Xcode 26.6 / Swift 6.3.3 on the M4 Pro Mac. Engineering version remains 0.1.0 (1).

Help → Privacy… presents a native localizable explanation of the app’s current local data handling. The window is created only on request, reused while open and released on close. The text is read-only but selectable, uses semantic system colors and wraps within a resizable scroll view. The existing auxiliary-window Close Window route keeps the editor draft open. The verified public privacy/support destinations and publisher-specific policy remain #15 release work.

## Executed checks

- Configuration/relative links, strict Swift formatting and diff checks pass.
- 45 repository tests pass (2.651 seconds); 85 core tests pass (0.866 seconds).
- Unsigned Debug build and universal arm64/x86_64 Release archive pass. Archive validation verifies version, icon, privacy resources, export metadata and absence of test/performance controls.
- A private sandboxed diagnostic links the exact changed app sources with the current Debug core object, replacing only the application entry point with the inspection driver. It uses its own bundle identity and UUID workspace. Exact four product entitlements and the binary hash match before and after execution.
- The app’s own Help action opens Privacy; opening again reuses the same window. Light/dark 600×580 and minimum 420×320 content views remain readable and scroll to the last paragraph. Initial text focus and complete text selection pass. Captures contain only the public privacy copy; no desktop or other application was inspected.
- The File menu Close Window action closes Privacy while retaining the generated draft and exact UTF-16 selection. Its controller is released. Reopening Privacy and requesting normal Quit through the host’s `NSRunningApplication.terminate()` completes; a fresh recovery-store load verifies exact draft bytes, selection, active tab, file state and empty closed history.

The completed diagnostic ran 23:34:18–23:34:20 UTC on September 8, with a 20-second host limit and 30-second outer bound. Raw sources, binaries, captures and fixture data are retained locally under `build/privacy-inspection-7DF049EC-30B6-45DA-B2DA-697EBEC2A401/`. The [numeric report](2026-09-09-offline-privacy.json) records provenance and every diagnostic observation.

The actual isolated DebugUITesting app also passes the complete existing cold-launch regression: mandatory UUID isolation, Finder file request, dirty draft recovery without overwriting the external file, normal Quit/restart and independent caret/scroll restoration. Its original 10-second observation bounds and all assertions are unchanged; the private host only retains failed fixtures and records their UUID. Exact sandbox/signature and executable hash pass before/after. Evidence: local `build/PrivacyCold-3869BD37-F03A-4858-B96D-23E1837FA5EA/`.

## Retained failures and limits

The initial sandboxed Xcode build could not write its normal compiler caches. A permitted build using those caches passed. XcodeGen also reproduced the existing missing-encryption-property defect now tracked separately in #69; this branch restores the existing audited plist and changes only the project’s new source-file entries.

Three earlier private inspection attempts reached the layout/close/release assertions but timed out on probe-initiated Quit. Stage recording showed the delegate returned `terminateLater` but its main-actor shutdown task never began while termination was called from inside the probe’s actor task/main-queue callback. The final host-issued Quit uses the same public termination route as the existing cold-launch driver and passes without changing app shutdown code, limits or assertions. All failed sources, binaries, observations and generated fixtures remain retained; their shutdown results are failures.

This is app-local menu/view/lifecycle inspection, not XCTest keyboard delivery, VoiceOver testing, public HTTPS validation or complete App Store acceptance. Full required self-hosted CI is pending on the Mac’s Automation Mode prerequisite. No release/upload or policy publication occurred.
