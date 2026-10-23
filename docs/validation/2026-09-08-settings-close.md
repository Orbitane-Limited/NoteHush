# Pending Settings edits on close

Issue #55. Branch `issue-55/settings-close-edit`, from main `2c786fac01a59e548475c20f985050c0a430e992`. Corrected app source: `4348c7c26ad907efd2f2b289d4e44f3975803e38`. Tests ran on macOS 26.6.2, Apple silicon, Xcode 26.6 during the user's explicit ten-hour native validation window. Version remains 0.1.0 (1).

## Reproduction and correction

Actual keyboard entry exposed the defect in the prior combined preparation app: after accepting 22 pt, enter 24 without Return, close Settings with Cmd+W, choose View → Zoom In and reopen Settings. The field returns to 22. Native window closure did not end the field edit, and a later workspace preference refresh could replace it.

The Settings controller now acts as its window delegate. On the native close notification it asks the field editor to resign, committing a valid number through the existing text delegate. If validation refuses invalid input, it ends that editing session and restores the last accepted size. It does not prevent closure or add a prompt. Existing Quit processing and pending-popup protection remain intact.

Two AppKit regressions use the real active field editor. The valid case covers window `performClose`, the standard close button and controller `close`, followed by another preference refresh and reopening. The invalid case covers empty, malformed and out-of-range input. Neither manually invokes the close notification or the text delegate being tested.

Against unchanged app code, both new cases **failed**, with twelve assertions showing uncommitted or stale values; the existing popup-order case passed. After the correction, the same three cases **passed**. Assertions, inputs and time limits were unchanged. The earlier failed result bundle is retained.

## Executed validation

- All **35 AppKit integration tests passed** once after the focused correction, in 17.060 seconds of test execution, with the existing 30/60-second case limits.
- All **28 repository tests**, **85 core tests**, and **83 Debug + 83 Release SIGKILL recovery drills** passed.
- Strict Swift formatting, configuration/relative links and diff checks passed.
- Debug build, unsigned universal Release archive and isolated optimized build-for-testing passed. The archive contains arm64 and x86_64; its executable SHA-256 is `270fd5176bb71486d5fd4a7d989e96f7f4fe869a54eee52806be599bae96675a`.
- The isolated test app was re-signed with the exact four product sandbox entitlements. Its existing ColdLaunchHarness passed cold file events, dirty-buffer preservation, restart and independent caret/viewport checks. Signature checks before and after the later manual work passed.

The repository counts differ from the combined preparation branch because this issue starts from main and includes only its own correction. The known tab-border deprecation remains in this branch; #54 addresses it separately. No unrelated change was bundled.

## Native app-window verification

The corrected build was launched through LaunchServices into generated UUID `8FB5764B-08B3-4F63-8000-1101AFD00882`, using the separate `pk.codehub.NoteHush.UITesting` bundle. The launcher verifies the exact bundle path/identity and does not access either clipboard. Only the generated Unicode source and draft were used.

1. Typed 22.5, closed Settings with Cmd+W, selected View → Zoom In and reopened: **22.5 and 110% both retained**.
2. Typed 24 and closed using the Settings close button: **24 retained on reopening**.
3. Typed invalid 100 and used the close button: **window closed without a prompt; reopening showed the last valid 24**.
4. Created an unsaved generated draft, entered 25.5 in Settings without Return and used Cmd+Q: **normal termination, no save prompt**.
5. Restarted the exact same UUID: **draft selected and intact, Settings displayed 25.5 and 110%**. Closing Settings and then the workspace with Cmd+Shift+W also terminated normally.

Both returned processes, 54468 and 62247, were verified stopped. Independent checks validated schema-6 checksums, every text blob, all three exact buffers, UTF-16 selections, window geometry and unchanged external source bytes. The final checkpoint retained the same verified state and increased from revision 12 to 16. Screenshots and accessibility states were inspected in the tool session; these are fixture observations, not Store screenshots.

## Evidence and limits

Local issue checkout: `build/run-settings-regression.sh`, `build/check-settings-headless.sh`, `build/logs/Settings-{before,after,full}.xcresult`, accompanying test/build logs and `settings-products.json` with every executable/library hash. The root checkout retains the generated manual fixture and sanitized before/final reports in `build/manual-acceptance/issue-55`.

Full XCUITest/GitHub CI and review remain pending because the earlier automation-initialization blocker is unresolved. Separate AppKit and manual passes do not replace them. Minimum-OS/Intel runtime, VoiceOver/real IMEs, performance budgets, real Store signing and installed TestFlight acceptance remain unverified release gates. No PR merge or App Store readiness is claimed.
