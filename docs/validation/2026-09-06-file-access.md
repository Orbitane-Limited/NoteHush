# Persistent file access and conflict validation

Issue #7, branch `issue-7/bookmarks-conflicts`, based on main `2a27f15`. Product version remains 0.1.0 (build 1), an unreleased development build. Environment: Apple silicon Mac, macOS 26.6.2, Xcode 26.6 (17F113), Swift 6.3.3; deployment target macOS 14.

## Scope

- App-scoped bookmarks created under active file access, persisted in schema 3 and lazily resolved on Save. Stale refresh changes authority/location without accepting external bytes. No remembered path alone grants access; resolution does not mount volumes or show system UI.
- Successful scoped accesses are balanced on success and failure. Bookmark creation failure after publication cannot turn a completed save into a reported failed write.
- Missing/denied sources offer Cancel, Relink and Save As. Relink keeps draft text and its original save baseline, and never writes the selected file.
- Changed sources show a bounded disk preview. Reload is undoable; Overwrite checks the reviewed identity/digest again. A newer external change blocks that overwrite. Unreadable content has no blind-overwrite action.
- Quit cancels file and conflict sheets, drains accepted publication, then checkpoints the draft without an unsaved-file confirmation.

## Executed validation

- `swift test`: 51 core tests passed, covering bookmark refresh/revocation, balanced failure paths, schema migration and a second edit after overwrite approval.
- `bash scripts/check.sh`: passed formatting, configuration/links, 51 core tests, 10 AppKit tests, 14 sandboxed UI scenarios (75 tests total), six SIGKILL recovery drills, the unsigned Debug build and the universal arm64/x86_64 Release archive. Version/privacy resources matched source.
- The real app saved across a folder move after relaunch and again after atomic replacement. Native tests exercised missing files, relink, Save As, permission denial, conflict preview, reload/undo, repeated overwrite review and Quit with a conflict sheet.
- The host mounted a disposable APFS image. A native panel granted access, explicit Save changed only the selected file, later unsaved text survived Quit, and the host detached the volume. A separate UI invocation restored that draft and offered Relink without remounting the volume. Fixture cleanup completed.
- Actual ad-hoc signed app entitlements contained App Sandbox, user-selected read/write and app-scoped bookmarks. Xcode disables hardened runtime with ad-hoc signing; that is not distribution-signing evidence.
- The conflict screenshot was visually reviewed. Retained screenshots are scoped to the NoteHush window; an initial broad local capture and its result bundle were removed. Text logs retain the full validation results; CI produces fresh result bundles with the corrected capture.
- After the full run, the harness gained per-checkout locking, interrupt cleanup and explicit checks that both volume phases passed. Standalone Xcode runs can skip unavailable host fixtures; required CI cannot. Final branch CI verifies these harness changes before merge.

Self-review covered permission lifetime, preserving content baselines during relink, duplicate destinations, explicit-only file publication, overwrite races and quit ordering. No independent reviewer approval is claimed. CI run links and retained verification artifacts are recorded on the associated pull request.

## Evidence limits and release gates

The first UI run passed the six new file-access behaviors and existing tests, but its volume setup failed before app testing: Xcode's sandboxed UI runner could not create an APFS image (`hdiutil: Device not configured`). Creating the same image from the host succeeded. Volume creation/detachment now belongs to the host harness, with mounted and offline UI phases; the app and test runner retain their sandbox entitlements.

Tests use only isolated generated files and unique test workspaces. The app is locally ad-hoc signed with App Sandbox, user-selected read/write and app-scoped bookmark entitlements. The APFS volume fixture is a disposable disk image, not a physical removable drive. Permission denial uses fixture mode bits; opaque bookmark revocation is also injected in core tests. Neither substitutes for TCC revocation testing.

Production Apple signing/hardened runtime, TestFlight, physical removable-drive tests, TCC-protected Desktop/Documents, network/file-provider volumes, macOS 14 runtime, Intel runtime, full VoiceOver validation and measured performance budgets remain M5/M6 gates. CI cross-compilation or an ad-hoc signature does not satisfy those release gates. No archive was submitted to Apple and no production GitHub release was created.

`NSFileCoordinator` and digest checks protect against detected changes and cooperating writers; they are not a universal filesystem compare-and-swap against an uncoordinated write occurring inside the final compare/publish interval. Full-snapshot recovery and large-text layout remain the documented M5 optimization work.
