# Native validation window — 2026-09-08

The user explicitly made this Mac available for ten hours, from 2026-09-07 23:45:26 through 2026-09-08 09:45:26 UTC. These observations are from its existing macOS 26.6.2 / M4 Pro environment. Engineering version remains 0.1.0 (1). This record covers completed checks through the first manual fixture's final termination, before issue #55's correction.

## XCTest automation initialization

The prepared #29 focused Find/Undo diagnostic was attempted once against its unchanged `d45b7b64512d3218aece6a067ca4c513d722081f` source and recorded binary. Disk headroom and exact test-app sandbox entitlements passed. The XCTest runner started at 23:47:27 UTC, then reported **“Timed out while enabling automation mode”** at 23:48:27. Xcode finished with exit 65 at 23:48:36. No NoteHush app, test setup or test method ran. The result bundle's failed-system-test count is not an app assertion failure.

The read-only Developer Tools check reported developer mode disabled; Xcode's first-launch check passed. This suggests an authorization prerequisite but does not conclusively establish the timeout's cause. No authentication policy, automation permission or security setting was changed. The user was asked to approve any pending Xcode automation request when available. The failed attempt is retained; no retry or timeout increase was used.

Local evidence in the #29 checkout: `build/logs/UndoDiagnostic-A6BC67BE-0012-41B5-99C1-66A0269C6E66.xcresult`, its log, `undo-diagnostic-startup-failure-summary.json`, and the authorized plan with the unchanged original source/binary hashes.

## Independent native integration checks

The combined app source was `03def2051f25a71566038fb5684bbad60ddc8d6b`, on documentation head `3e44140795d775886065873e78454170ed17bee1`. This evidence applies to the preparation branch, not current main or the separate #29 binary.

- **All 34 AppKit integration tests passed**, including printing/PDF, active and hidden editor layout, Unicode, independent Undo, preferences, file conflicts and recovery cases. They ran once in 20.298 seconds, with the existing 30/60-second case limits. The UI automation target was excluded from this separate test invocation; this is not a complete CI pass.
- The built isolated app was re-signed ad hoc with the exact four shipping sandbox entitlements. Checks before and after the following harness passed.
- **ColdLaunchHarness passed** isolation rejection, the cold file-opening event, dirty file recovery while external bytes differ, restart and independent offscreen caret/scroll restoration. It launched the exact `pk.codehub.NoteHush.UITesting` app through LaunchServices with generated UUID workspaces.

Local commands and results: `build/run_appkit_window_validation.sh`, `build/logs/AppKit-2026-09-07T2353Z.xcresult`, `appkit-window-{build,tests}.log`, `appkit-window-summary.json`, and `window-cold-launch-tests.log`. The result filename is a label; the AppKit tests actually ran approximately 23:52:44–23:53:07 UTC. The native product is under `build/WindowUITestDerivedData`.

## Separate app-window observations

Native computer-use actions targeted only the known test bundle and generated workspace `2D4C030C-C534-4428-B745-BD7D330F5944`. The source fixture was the published Find oracle `café CAFÉ café\r\n👩🏽‍💻 second\nlast`, never a user note. A second draft contained the generated text “Separate draft.”

| Observation | Result |
| --- | --- |
| Native Find next/previous, selection and wraparound | Observed with the exact accented query and four-character document selection |
| Replace one, case-sensitive Replace All and case-insensitive Replace All | All three produced the expected exact fixture text; immediate document Undo restored the original |
| Independent Undo after creating/switching to another tab | Original file restored; separate draft retained |
| Keyboard and pointer tab reordering | Order changed and restored; active editor identity, text and selection stayed intact |
| Close/reopen an unsaved tab | No confirmation; same tab identity, exact draft text and caret restored |
| About icon/version | Original icon rendered; 0.1.0 (1) displayed; publisher label is still provisional |
| Font family/face, appearance, zoom, wrap and spelling | Menlo Bold and both light/dark presentations observed; 200% and 250% text remained readable; pending-size-close defect found below |
| Cmd+Q with unsaved draft | App terminated without a save prompt; all three buffers and source bytes verified |
| Relaunch same UUID | Exact order, selected file, UTF-16 selection, scroll, committed preferences and window geometry restored; source unchanged |
| Native red workspace close | App terminated without a prompt; final checkpoint preserved the same verified state |

The first app process was 41285; the explicit same-UUID restart returned 45380. Both were verified terminated. Checksummed schema-6 metadata and every referenced text blob were verified against independent fixture bytes. Checkpoint revisions increased from 54 after Quit to 56 after restart and 57 after red close. The selected file's UTF-16 selection was location 0, length 14. The stored font size was 22, with Menlo Bold, Dark appearance, 250% zoom, wrapping off and spelling on. These committed values survived restart.

The opt-in Undo trace has 19 records, three Cmd+Z events and three matching editor will/did-Undo pairs, all returning to the exact original state, followed by normal shutdown. It contains classifications and booleans, not note text. This manual observation does **not** explain or resolve the prior intermittent XCTest Find failure, and its instrumented timings are not performance results.

## Defect found and fixture limitations

**Issue #55 remains open:** closing Settings with a valid pending size leaves it uncommitted. After a committed 22 pt baseline, actual keyboard entry of 24 followed by Cmd+W, View → Zoom In and reopening Settings displayed 22 again. The zoom change survived. The closed field editor's pending size can therefore be overwritten by a later preference refresh. Pressing Return commits the value correctly. No document text was changed by this defect.

The initial host helper launched the correct app but then compared directory URLs with different directory hints, rejected the returned identity and called `exit` before its cleanup defer. Its previous Find-pasteboard contents existed only in memory and could not be restored. The **Find** pasteboard was left with the generated query; the general clipboard was never accessed. This limitation was disclosed, and the helper was corrected to use explicit directory hints, throwing cleanup paths and checked conditional restoration. The corrected helper compiled but was not substituted retroactively for the failed run.

The first computer-use app connection took approximately 2 hours 51 minutes. No acceptance work is claimed during that tool wait. The initial displayed fixture then contained one unexplained leading space; its external source bytes were still original. The controlled checks above began only after restoring and verifying the exact public oracle. Computer-use keyboard entry also omitted the accented character once; the Find field was explicitly set to the exact query and verified before testing. These inputs do not certify dead-key or IME support.

Local retained evidence is under the root checkout's `build/manual-acceptance/2026-09-07T2356Z`: sanitized before/restart/final JSON, the 19-record diagnostic, source oracle and manifest with the host failure. The inspector excludes bookmarks and file bindings from its reports. Screenshots and accessibility observations were inspected in the tool session; they are development-fixture evidence, not final Store screenshots.

## Remaining acceptance

Full native CI, the intermittent Find diagnosis, #55 correction, measured performance, VoiceOver, real IME/dead keys, contrast/reduced-motion system settings, minimum-OS/Intel/reference hardware, real signed installation/TestFlight and physical printing remain open. Pointer reorder passed, but the transient insertion-line appearance during an in-progress drag was not captured. No release gate or issue was closed by these separate manual observations.
