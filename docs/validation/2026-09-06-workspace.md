# Tabs and session lifecycle validation — 2026-09-06

Scope: issue #5, branch `issue-5/tabs-session-lifecycle`, development version 0.1.0 (1). Hardware: this Apple silicon Mac, macOS 26.6.2; Xcode 26.6 (17F113), Swift 6.3.3. The PR and its linked GitHub runs identify the exact tested commits.

## Executed checks

- `bash scripts/check.sh`: strict Swift formatting, configuration checks, 29 core tests, six child-process SIGKILL drills, AppKit integration, sandboxed XCUITests, unsigned Debug build and universal arm64/x86_64 Release archive passed.
- `bash scripts/test_app.sh`: after adding the final failure-injection case, four AppKit integration tests and two XCUITests passed. The script verifies the actual test app retains `com.apple.security.app-sandbox = true`.
- Core scheduler tests exercise 250 ms debounce, the independent 500 ms maximum scheduling timer, immediate-edit-then-quit, repeated shutdown, slow in-flight writes with replacement of pending snapshots, failed writes and successful retry. Tests use an injected clock and gated writer, not wall-clock sleeps.
- AppKit tests restore selection and a line-150 scroll anchor across tab switches and relaunch; clamp a window from a disconnected display; verify independent undo; preserve future-schema bytes and losslessly export both generations; and confirm failed final writes show a warning while keeping draft text and returning from shutdown.
- XCUITests create three drafts, check tab identities/order, switch tabs, verify independent undo, quit/relaunch with an active selection, replace that restored selection, quit immediately after editing and recover it. A separate test clicks the red close button and verifies text/window dimensions after relaunch without a confirmation dialog.
- Six crash drills terminate a child writer at offsets from 0–20 ms after a checkpoint acknowledgement. Every restored snapshot contains complete expected text and a revision at least as recent as every acknowledged revision.
- Visual review of the retained “Three native tabs” screenshot: tab titles and selected state are visible, editor text has clear contrast, and the window layout fits its bounds. The screenshot contains synthetic fixture text only.

The scroll integration test initially caught a real origin/viewport bug: detached text layout could place the document at a negative origin, constraining restoration to the wrong location. The fix restores a zero document origin, suspends observation during presentation and then reapplies the text anchor. The original scroll assertion now passes. The initial UI query assumed plain buttons; native tab controls expose selectable roles, so queries now use stable accessibility identifiers.

The first write-failure fixture attempted to remove directory write permission. Recovery intentionally restores private directory permissions, so that did not inject a failure. The final test uses the existing recovery I/O boundary to fail writes deterministically; it retains the original assertions about the warning, old checkpoint and in-memory draft.

## Limits and remaining release gates

Ad-hoc signing is local test execution, not App Store signing. Xcode disables hardened-runtime enforcement for ad-hoc signing; signed runtime, TestFlight, minimum macOS and Intel hardware verification remain open. No new data collection, network permission or required-reason API was introduced. User-selected read/write access is used for the explicit recovery export panel.

Native export-panel destination selection, full VoiceOver/IME coverage and broader fault drills remain part of M5/M6 acceptance. Full-workspace checkpoint serialization and full layout on initial scroll restoration remain optimization work in #12. No launch/typing budget, universal zero-loss guarantee or 500 ms worst-case recovery bound is claimed from these tests. Tab closing/reordering/history, file open/save, preferences, search and store assets remain in their existing issues.

Self-review covered the changed source, race/failure paths, sandbox configuration and generated project. No independent human review has occurred. No production tag or GitHub release was published.
