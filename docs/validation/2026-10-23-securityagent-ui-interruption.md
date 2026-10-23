# Unidentified SecurityAgent interruption during UI validation

Date: 2026-10-23. Issue #29. GitHub Actions run [39905337666](https://github.com/Orbitane-Limited/NoteHush/actions/runs/39905337666), from the draft CI-artifact policy change in PR #78.

The self-hosted Apple Silicon runner completed its disk preflight and the non-UI `NoteHushAppTests` suite (34 tests, 0 failures). Four UI tests failed because expected controls or values were not observed:

- `EditingTests.testFindInOneMiBDocumentKeepsTabsAndNavigationUsable`
- `EditingTests.testGoToLineStatusAndQuitWithSheetOpenPreserveDraft`
- `FileAccessTests.testDeletedFileRelinkThenSaveAsKeepsDraftAndOtherFile`
- `PreferencesUITests.testSettingsFontAppearanceWrapSpellingZoomAndQuitPersistence`

The run’s activity and console records repeatedly show a window owned by `com.apple.SecurityAgent` while NoteHush and Settings are reported disabled. XCTest reported that no interruption monitor handled it. The dialog’s title/message and its cause were not established. No one inspected, approved or dismissed the dialog during that run, and the setting was not changed by the agent. The failures therefore remain unexplained; they are not classified as product defects or successful UI validation.

The self-hosted failure artifact upload was rejected because the organization’s Actions artifact-storage quota had been reached. On 2026-10-23 the owner made the repository public and a later GitHub-hosted macOS 26 / Xcode 26.6 run uploaded a 127,912,842-byte failure artifact successfully. That later run reached the UI suite and reported one failure: `PreferencesUITests.testSettingsFontAppearanceWrapSpellingZoomAndQuitPersistence`. Its log also contains generic XCTest text that no interruption monitor handled a UI interruption, but it does not establish that interruption's relation to the failing case or identify the dialog. The result bundle was not available to the agent's shell for inspection during this follow-up.

No retry, assertion change, timeout extension, interruption handler expansion or system-dialog dismissal was performed. After the original self-hosted run, the owner enabled Automation Mode with the documented administrator command and ran `python3 scripts/check_ui_automation.py` from an interactive Terminal; that preflight passed. A subsequent invocation from the agent's execution shell still reported Automation Mode disabled. These results are from different execution contexts and do not establish the self-hosted runner's status. The hosted rerun does not resolve the cause: its Automation Mode status was not recorded, the dialog's message and cause remain unknown, and the failed preference expectation has not yet been identified. PR #78 remains failed; passing AppKit tests and partial UI success do not establish release readiness.
