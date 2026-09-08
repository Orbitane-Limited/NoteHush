# Native folder-panel input investigation

Issue [#50](https://github.com/Orbitane-Limited/NoteHush/issues/50), NoteHush 0.1.0 (1). This candidate changes only native UI-test setup. It removes the Go to Folder helper's click and Select All operation, enters the same generated path in the field's initial selection, and checks the complete field value before Return. App code, sandbox entitlements, file fixtures, original content/recovery assertions and one-minute test limits are unchanged. All three focused native cases pass; complete final-head CI remains required.

## Retained failure

[PR #47 CI attempt 3](https://github.com/Orbitane-Limited/NoteHush/actions/runs/34103461450/attempts/3) ran on clean candidate `2a56099641aceee5865fb14e34f8ef4525104f1c`, merge-test `0a00557d5e0ef3533724db110c54a76e3dd2bc96`. It reports 60 native passes, one failure and zero skipped cases. `FilePanelTests.testNativeOpenAndSaveAsPreserveMixedNewlinesAndChosenExtension` exceeded the original 60-second limit. Its later console line says passed at 61.508 seconds, but the completed result correctly retains the timeout as a failure.

The generated-path entry took 17.3269 seconds in event synthesis; Select All in that field took 5.11725 seconds. The earlier Open shortcut took 5.86325 seconds, and the test daemon explicitly recorded a five-second implicit event-confirmation interval for it. This identifies configured confirmation work in that action, not proof of the cause of every input delay. A read-only secure-event-input Boolean was false at 13:55 UTC; its state during earlier actions was not recorded. No global preference, timeout or clipboard was changed.

28 repository tests, 85 core tests, 166 crash drills, cold launches and all 34 AppKit cases passed. The two previously failing Go to Line/bookmark cases passed both a focused diagnostic and this full CI attempt. Offline-volume, later Debug/archive and optimized-build stages were not reached. Verification artifact `10021781800`, `validation-0a00557d5e0ef3533724db110c54a76e3dd2bc96`, contains 83,640,286 bytes. Complete local logs and `Lifecycle-1C13418F-87B1-4BE9-A77F-36D3E305C4CC.xcresult` are retained under root `build/validation-issue46-2a56099-attempt3/`.

## Scope and validation gate

This branch starts from main `2c786fac01a59e548475c20f985050c0a430e992`; the separate scrollbar fix is not bundled. `XCUIElement.typeText` requires keyboard focus and fails without it. The new Boolean assertion checks replacement of any pre-existing field value without printing actual contents. The installed public XCUIAutomation header exposes no macOS `hasFocus` property; no private substitute is used.

Apple documents [native keyboard entry through `typeText`](https://developer.apple.com/documentation/xcuiautomation/xcuielement/typetext(_:)) and [entering a path after opening Finder's Go to Folder](https://support.apple.com/guide/mac-help/go-directly-to-a-specific-folder-mchlp1236/mac). The Finder guide does not certify selection behavior in the remote file panel; that remains an explicit native validation gate here. The installed `XCUIElement.h` and `XCUIElementAttributes.h` declarations were also checked on 2026-09-07.

Before acceptance, the dedicated native Open/Save As, bookmark and relink cases must pass with exact file bytes and restart checks, followed by complete final-head CI including both volume phases. The candidate must be rejected or revised if native initial selection is not reliable. No failed result may be hidden by an unconditional retry or relaxed assertion. The historical session-handoff delay, unidentified system dialog and broader input-reliability findings remain open in #29; hardware, accessibility, signing and App Store release gates remain unverified.

## Preparation checks

Strict formatting of both changed Swift files, configuration/link validation and diff checks pass. Build-for-testing also passes, followed by re-signing and verification of exactly the four product entitlements. The build did not launch the app or a test. Evidence is in this issue checkout's `build/logs/native-folder-build.log` and `test-app-entitlements.plist`. This was the candidate on the main base above with its two helper changes uncommitted; compilation does not verify the native field-selection assumption.

The first 20-minute operator input window ended after CI attempt 3. The branch was retained remotely without opening a PR or starting another GUI run while a further window was pending. The user instructed continuation at approximately 14:39 UTC after the next explicit awake/unlocked exclusive-input request. Actual input was not continuously monitored. The self-hosted runner was online/idle, no isolated NoteHush test process was active, and storage passed before and after building (122,859,163,648 bytes free after building versus 49,438,479,565 required).

## Focused native validation

Clean source `d81393144e5f55c7d93d627314b214a0f0294273` rebuilt successfully with Xcode's `build-for-testing`, then ran the three cases below through `test-without-building` in `DebugUITesting`, arm64, with parallel testing disabled and the unchanged 30-second default/60-second maximum allowances. The app executable SHA-256 was `a209098a0535ba6cf382709d470f0b64208dbc6ec54b568957c159198f1cfe6f`. Re-signing and exact product-entitlement verification passed before testing, and a fresh signature/entitlement check passed afterward.

| Native case | Result | Duration |
| --- | --- | ---: |
| `FileAccessTests.testBookmarkFollowsMoveAcrossFoldersAfterRestartAndRefreshesAfterSave` | Pass | 34.531 s |
| `FileAccessTests.testDeletedFileRelinkThenSaveAsKeepsDraftAndOtherFile` | Pass | 29.970 s |
| `FilePanelTests.testNativeOpenAndSaveAsPreserveMixedNewlinesAndChosenExtension` | Pass | 35.910 s |

The completed xcresult reports three passes, zero failures and zero skipped tests. The exact-path assertions demonstrate that the initial field selection accepted replacement text in both helpers and across the Relink/Save As flow on this host. Every existing source/destination byte and restart assertion remains intact. These are functional observations, not a controlled performance comparison or proof against every future input interruption.

Evidence remains in this checkout's `build/logs/NativeFolder-10281D10-0B91-4B89-BD76-B55571762D9B.xcresult`, `native-folder-focus-build.log`, `native-folder-focus-tests.log`, and the adjacent provenance/summary JSON files. No disposable volume fixture was needed for this focused selection; complete CI must still execute the mounted and offline phases and all remaining checks. The PR remains draft until its exact final source passes those requirements and review feedback is resolved.
