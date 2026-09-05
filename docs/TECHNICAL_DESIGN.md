# Technical Design Document

## Architecture

Use AppKit for application lifecycle, native menus/windows and `NSTextView` editing. Keep the recovery and document model in a Foundation-only local Swift package. SwiftUI is optional for isolated preferences views; do not embed a web editor. Deployment target macOS 14; Swift 6 concurrency; Xcode 26.6 initial toolchain.

```
App/NoteHush/
  Application/        App delegate, commands, composition
  Workspace/          Window controller, tab bar, panels and file command integration
  Editor/             NSTextView, search, status, selection
  Preferences/        Display and editing preferences
  Resources/          Assets, localized strings, privacy manifest
Sources/NoteHushCore/
  Models/             Workspace, tabs, text format, revisions
  Files/              Strict text codecs, file identity, scoped coordinated I/O
  Recovery/           Serialized checkpoint store, schema, validation
Tests/NoteHushCoreTests/
Tests/NoteHushUITests/
Config/               Version.xcconfig, entitlements
scripts/              check.sh, archive/release validation
.github/              Workflows, issue forms, PR template
docs/                 Product, architecture and operational evidence
```

## State ownership and data flow

`WorkspaceController` is main-actor isolated and owns ordered tab identities and active selection. A tab owns its text storage, undo manager, presentation state, revision, optional file binding, and saved revision. Dirty status compares current content revision/digest with the explicit-file-save baseline; editing back to identical content must clear dirty status.

AppKit edits update only the active tab. Capture an immutable snapshot after a 250 ms debounce with a 500 ms maximum checkpoint interval during continuous input. A serialized recovery actor persists snapshots away from the main actor. Stale revisions must not overwrite newer revisions. Status calculations are incremental or debounced; no whole-workspace JSON encoding on each keystroke.

Session metadata uses stable UUIDs, ordered tabs and active tab ID. Selection offsets are UTF-16; validate against NSString length. Scroll restoration uses a text anchor plus offset rather than assuming layout is identical after fonts or display size change. Record window frame and clamp to available screens. Keep text undo history in memory per tab; persisting undo stacks is outside v1.

## Recovery storage and crash consistency

Private root: the sandbox's Application Support/NoteHush/Recovery directory, resolved using Foundation rather than constructing a user home path. Use user-only permissions. Never store drafts in preferences, the repository, shared tmp, or a cloud container.

The initial store implementation may use atomic, versioned full-workspace snapshots to prove invariants; it is a correctness foundation, not the final performance design. Before M5 performance acceptance, use immutable per-tab revision blobs and a small atomic manifest so unchanged tabs are not rewritten.

Issue #4 implements the initial schema-1 full snapshot: `session.json` and `session.previous.json`, each containing version, payload and SHA-256. An actor plus an advisory disk lock serializes writers. Commits reread revisions under lock, flush private temporary files, rename atomically and synchronize the directory. Damaged generations are copied to uniquely named evidence files before replacement. Unsupported schemas in either slot block writes. A 256 MiB encoded-envelope guard bounds this interim format; large-workspace efficiency and evidence retention policy must be addressed before release in M5. Issue #5 adds optional scroll anchors and window bounds. Issue #6 writes schema 2 for file bindings, reads schema 1, and retains the previous raw schema-1 generation during migration. Older schema-1 builds block on the newer store instead of dropping file metadata. Preferences follow in #9.

The UI now owns one `EditorTab` per tab, each with its own AppKit text system and undo manager. `CheckpointCoordinator` maintains one in-flight write and replaces a pending snapshot with the newest revision. Its 250 ms debounce and 500 ms maximum scheduling interval are independent; replacing a timer never cancels an active write. Shutdown freezes editing, commits marked text, captures the final state, drains the writer and always replies to terminate, including after a failed write. Window close routes through that same application termination path.

No editable workspace is created until recovery loading succeeds. Unknown schemas and unreadable stores retain a persistent warning and prohibit editing; Retry reloads, and Export copies the original generations into a lossless JSON dictionary of base64 bytes. A write failure keeps editable drafts and offers Retry or an all-tab JSON snapshot export through `NSSavePanel`. Export never replaces private recovery data. The user-selected read/write entitlement supports that explicit panel; no broad filesystem permission is used. Fallback notices remain visible throughout the session. Full layout during initial scroll restoration and full snapshot encoding remain optimization work for #12.

Commit protocol for final store:

1. Serialize and validate changed tab blobs. Write temporary files in the recovery directory; flush contents before publishing.
2. Atomically install immutable blob names containing stable IDs and revision identifiers.
3. Write and atomically replace a checksummed manifest referencing a complete set of blobs. Keep the last valid manifest as fallback.
4. Only then report checkpoint success and update the persisted revision. Clean up unreachable generations after at least two valid manifests exist; never delete evidence during recovery failure.

Readers validate schema, checksum, unique IDs, nonempty/valid active selection, sane byte/range limits, and completeness. Validate payload bytes before decoding. A truncated or mismatched primary falls back to a verified backup and informs the UI. Preserve damaged artifacts. Unknown future schema prohibits writes, including autosave. A migration writes a new generation and retains old files until verified. Do not interpret an unreadable existing store as a fresh install.

Normal termination uses `applicationShouldTerminate`: return terminateLater, flush the latest immutable state, then reply to terminate. Never show an unsaved-file dialog. A failed flush is visible before exit where possible; NH-02 still requires exit. A recovery warning during editing is essential because no implementation can guarantee persistence on a failing disk while also guaranteeing unconditional quit. The final implementation must test shutdown racing a pending debounce, repeated quit and I/O failure. Window close follows the same path instead of triggering NSDocument save prompts.

Recently closed tabs are recoverable, capped at 20. Clear-history must be explicit; garbage collection may remove their content only after the new manifest commits. Provide an explicit reset/clear workflow so local persistence is understandable to users.

## External file safety

Implemented in #6: `TextFileService` is an actor that balances security-scoped access, coordinates reads/replacements and captures device/inode plus SHA-256 baselines. Descriptor validation rejects special files and files over 100 MiB before coordination (which itself can block on a FIFO), and again before allocation/read. Reads check cancellation in 64 KiB chunks; the UI discards late cancelled results. Waiting inside OS file coordination is not instantly cancellable. Files over 20 MiB show a notice; layout and memory budgets remain #12 work.

Open/Finder requests queue behind recovery loading. A duplicate identity or canonical path selects the existing tab without replacing its recovered text or save baseline. Save captures immutable text before awaiting I/O; edits made during the write stay dirty. Debounced off-main digest comparison clears dirty state after undo restores exact saved bytes. Save As exposes encoding choice and preserves the chosen extension. Atomic writes update file metadata only after success, reject changed/deleted source baselines, and protect other open tabs. Failure keeps the draft and baseline. Quit cancels pending opens, dismisses file panels and drains an accepted save before the final private checkpoint.

File bindings persist format/identity/digests and a location for display and conflict checks. Stored paths grant no sandbox authority. In #6 only panel/Finder access survives in memory; after relaunch Save requires a panel. Persistent bookmarks, relink and inspect/reload/explicit-overwrite conflict choices remain #7. The current conflict banner offers Save As and never silently overwrites a changed source.

Use NSOpenPanel/NSSavePanel, user-selected read/write entitlements, security-scoped bookmarks, balanced start/stop access and NSFileCoordinator. Bookmarks are opaque local data and are never logged. Refresh stale bookmarks after successful resolution. A revoked/missing source retains the recovery buffer and requests relink only when accessing/saving that file.

On open, record file identity and a digest of original bytes. Preserve decoded text exactly and track BOM/encoding/newlines separately. At save, coordinate access, compare current file content/identity to the baseline, and require an explicit conflict choice if changed. Atomic replacement in the same directory must retain correct sandbox authority and permissions. Error paths never clear dirty state. Recovered content is authoritative for dirty buffers; external files are not blindly reread on launch.

Support UTF-8 with/without BOM and BOM-marked UTF-16 LE/BE. Reject unsupported/invalid bytes rather than substituting U+FFFD. Preserve CRLF/LF/CR including mixed input. Encoding conversion is a user operation, never a side effect of display settings. File-size guard is checked before allocation; background loading is cancellable and does not mutate a tab until valid.

## Security, privacy and distribution

Enable App Sandbox and hardened runtime, disable network/device entitlements, never execute document contents, and use public SDK APIs. Privacy manifest must describe actual required-reason API use; do not copy declarations for unused APIs. Audit the built app, not just source plist. No third-party runtime libraries initially. A privacy-policy page and public support URL are required store assets even though the source repository is private.

Bundle identifier proposal: `pk.codehub.NoteHush`; confirm it under the user's Apple team before registration. `Config/Version.xcconfig` is version source of truth: marketing `0.1.0` initially, monotonically increasing integer builds for uploads. Universal builds must be checked with lipo; Intel runtime validation is separate. GitHub Actions runs unsigned verification; signed delivery uses a protected environment, short-lived keychain, scoped App Store Connect credentials and cleanup. See APP_STORE and RELEASING.

## Alternatives and risks

NSDocument would reduce native file-management code, but autosave-in-place and save prompts diverge from the private draft model. SwiftUI TextEditor offers less direct control over undo, find, large text and selection. SQLite is an option if measured recovery workloads justify it; introduce it via a documented migration, not as premature infrastructure. Full snapshots are acceptable only as an explicitly measured initial implementation. Primary risks are persistence races, memory duplication, bookmark loss, external conflicts, IME regressions and unsupported claims of performance.

## References

- [Apple NSDocument](https://developer.apple.com/documentation/appkit/nsdocument)
- [Apple NSTextView](https://developer.apple.com/documentation/appkit/nstextview)
- [Apple App Sandbox](https://developer.apple.com/documentation/security/app-sandbox)
- [Apple NSFileCoordinator](https://developer.apple.com/documentation/foundation/nsfilecoordinator)
- [Apple privacy manifests](https://developer.apple.com/documentation/bundleresources/privacy_manifest_files)
- [Apple approved required-reason API uses](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitypereasons)
- [Apple deferred termination reply](https://developer.apple.com/documentation/appkit/nsapplication/reply(toapplicationshouldterminate:))
- [Apple termination while a sheet is open](https://developer.apple.com/documentation/appkit/nswindow/preventsapplicationterminationwhenmodal)
- [Apple per-text-view undo manager](https://developer.apple.com/documentation/appkit/nstextviewdelegate/undomanager(for:))
- [Apple text view in a scroll view](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/TextUILayer/Tasks/TextInScrollView.html)
