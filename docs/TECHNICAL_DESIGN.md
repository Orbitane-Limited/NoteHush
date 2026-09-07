# Technical Design Document

## Architecture

Use AppKit for application lifecycle, native menus/windows and `NSTextView` editing. Keep the recovery and document model in a Foundation-only local Swift package. SwiftUI is optional for isolated preferences views; do not embed a web editor. Deployment target macOS 14; Swift 6 concurrency; Xcode 26.6 initial toolchain.

```
App/NoteHush/
  Application/        App delegate, commands, composition
  Workspace/          Window controller, tab bar, panels and file command integration
  Editor/             NSTextView, search, status, selection
  Preferences/        Display and editing preferences
  Printing/           Native print sheets and independent paginated text snapshots
  Resources/          Assets, localized strings, privacy manifest
Sources/NoteHushCore/
  Models/             Workspace, tabs, text format, revisions
  Files/              Strict text codecs, file identity, scoped coordinated I/O
  Editing/            Unicode text metrics and sparse navigation index
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

## Editor layout and scroll restoration

Attach each empty `NSTextView` to a positively sized `NSScrollView` before assigning recovered text. Applying preferences while empty avoids invalidating the content style of an already populated, detached text view. A generated 256 KiB Arabic/combining-mark/emoji draft exposed prolonged bidirectional typesetting in that former attachment order; changing only the scroll view dimensions did not resolve it.

Each editor's `NSLayoutManager` permits noncontiguous layout and disables idle background layout. Hidden tabs retain their text and UTF-16 selection without typesetting it. Selecting a tab lets AppKit lay out the requested viewport; restoration does not request the entire text container or every character preceding the saved anchor. TextKit may expand requested ranges as necessary, and a very long paragraph can still be expensive.

Native `scrollRangeToVisible` establishes the saved text anchor before document sizing and the saved vertical/horizontal offsets are applied. This is necessary because laying out a single character can leave a stale estimated scroll origin after the visible area is typeset. Scroll state remains a character anchor plus offset, independent of estimated total document height. Presentation changes preserve the original text snapshot, file baseline, selection and undo history.

Restore the selected viewport before giving the text view keyboard focus. AppKit updates the insertion point when a text view becomes first responder; focusing it before its viewport is established caused expensive bidirectional layout in the generated mixed-script workspace. The saved selection and viewport remain independent: a caret may legitimately be offscreen. Native cold-launch checks preserve both across restart, including opposite ends of a 256 KiB mixed-script draft. See the [focus investigation](validation/2026-09-07-editor-focus.md).

See the [layout investigation](validation/2026-09-07-editor-layout.md) for reproduction and validation. Public API references reviewed 2026-09-07: [NSLayoutManager](https://developer.apple.com/documentation/appkit/nslayoutmanager), [noncontiguous layout](https://developer.apple.com/documentation/appkit/nslayoutmanager/allowsnoncontiguouslayout), [background layout](https://developer.apple.com/documentation/appkit/nslayoutmanager/backgroundlayoutenabled), and [native text scrolling](https://developer.apple.com/documentation/appkit/nstext/scrollrangetovisible(_:)). Signatures and layout semantics were also checked in the installed macOS SDK headers.

## Recovery storage and crash consistency

Private root: the sandbox's Application Support/NoteHush/Recovery directory, resolved using Foundation rather than constructing a user home path. Use user-only permissions. Never store drafts in preferences, the repository, shared tmp, or a cloud container.

The initial store implementation may use atomic, versioned full-workspace snapshots to prove invariants; it is a correctness foundation, not the final performance design. Before M5 performance acceptance, use immutable per-tab revision blobs and a small atomic manifest so unchanged tabs are not rewritten.

The [schema-5 baseline](validation/2026-09-07-recovery-baseline.md) records 20-sample Release measurements on an M4 Pro. A 30 MiB workspace's selection-only checkpoint reads and rewrites about 90 MiB at the recovery API boundary and takes 1.02 seconds at p95. The [schema-6 comparison](validation/2026-09-07-recovery-comparison.md) reduces that storage-only p95 to 8.04 ms after the per-tab migration in #31. These storage-only timings do not certify app responsiveness or the lost-input bound; whole-app performance remains #12 work.

Issue #4 implements the initial schema-1 full snapshot: `session.json` and `session.previous.json`, each containing version, payload and SHA-256. An actor plus an advisory disk lock serializes writers. Commits reread revisions under lock, flush private temporary files, rename atomically and synchronize the directory. Damaged generations are copied to uniquely named evidence files before replacement. Unsupported schemas in either slot block writes. A 256 MiB encoded-envelope guard bounds this interim format; large-workspace efficiency and evidence retention policy must be addressed before release in M5. Issue #5 adds optional scroll anchors and window bounds. Issue #6 writes schema 2 for file bindings, reads schema 1, and retains the previous raw schema-1 generation during migration. Older schema-1 builds block on the newer store instead of dropping file metadata. Issue #7 writes schema 3 with optional opaque bookmark data, reads schemas 1–3 and retains the prior raw generation during migration. Schema-2 builds refuse the new store instead of dropping persistent authority. Issue #9 writes schema 4 for display preferences and horizontal scroll restoration (see below).

The UI now owns one `EditorTab` per tab, each with its own AppKit text system and undo manager. `CheckpointCoordinator` maintains one in-flight write and replaces a pending snapshot with the newest revision. Its 250 ms debounce and 500 ms maximum scheduling interval are independent; replacing a timer never cancels an active write. The production timer performs its sleep directly inside the task; an optional injected sleeper is reserved for deterministic scheduler tests. This avoids a reproducible Swift 6.3.3 runtime crash when an async default-argument sleeper closure is invoked by the linked continuous-input harness. The 250/500 ms timing policy is unchanged. Shutdown freezes editing, commits marked text, captures the final state, drains the writer and always replies to terminate, including after a failed write. Window close routes through that same application termination path.

No editable workspace is created until recovery loading succeeds. Unknown schemas and unreadable stores retain a persistent warning and prohibit editing; Retry reloads, and Export copies the original generations into a lossless JSON dictionary of base64 bytes. A write failure keeps editable drafts and offers Retry or an all-tab JSON snapshot export through `NSSavePanel`. Export never replaces private recovery data. The user-selected read/write entitlement supports that explicit panel; no broad filesystem permission is used. Fallback notices remain visible throughout the session. Startup latency, deep-scroll latency and peak memory remain measured acceptance work for #12; editor construction and restoration use the on-demand layout path described below.

Commit protocol for final store:

1. Serialize and validate changed tab blobs. Write temporary files in the recovery directory; flush contents before publishing.
2. Atomically install immutable blob names containing stable IDs and revision identifiers.
3. Write and atomically replace a checksummed manifest referencing a complete set of blobs. Keep the last valid manifest as fallback.
4. Only then report checkpoint success and update the persisted revision. Clean up unreachable generations after at least two valid manifests exist; never delete evidence during recovery failure.

Readers validate schema, checksum, unique IDs, nonempty/valid active selection, sane byte/range limits, and completeness. Validate payload bytes before decoding. A truncated or mismatched primary falls back to a verified backup and informs the UI. Preserve damaged artifacts. Unknown future schema prohibits writes, including autosave. A migration writes a new generation and retains old files until verified. Do not interpret an unreadable existing store as a fresh install.

Normal termination uses `applicationShouldTerminate`: return terminateLater, flush the latest immutable state, then reply to terminate. Never show an unsaved-file dialog. A failed flush is visible before exit where possible; NH-02 still requires exit. A recovery warning during editing is essential because no implementation can guarantee persistence on a failing disk while also guaranteeing unconditional quit. The final implementation must test shutdown racing a pending debounce, repeated quit and I/O failure. Window close follows the same path instead of triggering NSDocument save prompts.

Recently closed tabs are recoverable, capped at 20. Clear-history must be explicit; garbage collection may remove their content only after the new manifest commits. Provide an explicit reset/clear workflow so local persistence is understandable to users.

## Schema-6 immutable text recovery

Issue #31 writes small checksummed manifests into the existing primary/previous slots. Each tab contains its metadata and a SHA-256 reference with UTF-8 byte count and UTF-16 length. The filename is derived from a canonical tab UUID and validated lowercase digest: `blob-<UUID>-<digest>.utf8`. No path from a manifest is opened. Raw UTF-8 preserves literal U+FEFF and canonical Unicode differences; decoding checks exact round-trip bytes, digest and lengths. Open tabs, closed history, file bindings/bookmarks, preferences and presentation fields retain their existing representation. True schema-1–5 inline-text envelopes remain readable; migration retains the prior raw generation, except when an explicit clear/eviction requires post-publication backup pruning. Same-revision migration also publishes schema 6. Older builds refuse version 6.

`TabSnapshot` retains its original flat Codable shape for legacy data, editable-draft exports and independent test oracles. A private, nonserialized UUID identifies each captured String value; copying a snapshot keeps that identity, and assigning text replaces it. `EditorTab` caches its captured snapshot and invalidates text on `NSTextStorage` character-edit notifications, including direct changes and marked text; capture also checks pending character edits inside a storage batch before its notification arrives. Selection, scroll, bindings and preferences do not copy every background editor's text. The recovery actor caches derived references only for the incoming snapshot identities; it does not retain an additional full-workspace text copy. General snapshot validation still counts real UTF-16 units; the checkpoint path can reuse a previously computed length for the same immutable identity.

Every commit rereads both manifest headers, checksums and revisions under the disk lock. Verified blob metadata can be reused only while the reference and regular-file fingerprint match: device/inode, byte size, mode/owner/group, and nanosecond modification/change timestamps. Changed or missing files invalidate this cache; an I/O failure or conflict clears it. Every load/Retry verifies actual blob bytes, sharing reads only for identical references within that load. This in-process immutable-file cache is not a guarantee against hardware corruption that leaves filesystem metadata unchanged. Unknown schemas always block writes and cleanup before cache reuse can affect publication.

Changed blobs are written through the existing temporary-file, file-sync, rename and directory-sync sequence before backup/current manifests. Metadata-only checkpoints write no blobs; a one-tab edit writes only its new text. Previous/current manifests retain their referenced blobs. After primary publication, history removal first compacts the backup; reclamation then removes only exact managed blob filenames that neither valid generation needs. An unlink and its directory sync are observable failure boundaries. Failed cleanup and synchronization remain retryable at the same revision; visibility after rename/unlink never by itself earns an acknowledgment.

Before replacing a damaged generation, copy every currently present managed blob into a finite evidence bundle with a shared `damaged-<UUID>--` prefix, then copy the original raw manifest last. This preserves even references that cannot be parsed, without retaining every future blob forever. A failure during copying leaves the original slot untouched. An existing corrupt blob is likewise copied before repair. Evidence bundles, unrecognized names and `.pending-*` interrupted writes are never automatically deleted. Ordinary unreachable managed blobs can be reclaimed only after complete manifests are published. A crash before the first manifest may leave unpublished blobs; they do not represent an acknowledged workspace and survive until a later complete checkpoint permits reclamation. Clearing history is not secure erasure and never removes damaged evidence.

Individual recovery files and aggregate declared workspace text are bounded at 256 MiB. Manifest bounds are checked before blob hydration. Readers reject symlinks/special files with descriptor checks, nonblocking/no-follow opens and stable-file metadata validation. Raw export enumerates all recovery-root entries except the writer lock, including blobs, damaged bundles, unknown files and interrupted writes, and verifies every entry can be read. The JSON export preflights a 512 MiB aggregate raw-byte limit; unsupported objects, missing entries or oversized exports fail visibly and leave originals intact instead of producing an incomplete success. The limit bounds allocation, not a claim that a workspace near this size meets performance budgets. Evidence is retained indefinitely pending an explicit future user-facing policy; repeated storage damage can grow disk use or make this bounded export unavailable.

## Tab management and recent history

Issue #10 writes schema 5 with optional `closedTabs`, reading schemas 1–5. Each closed value holds its `TabSnapshot` and original index; newest first, capped at 20. Validation rejects duplicate identities across open/history, excessive history, negative indices and invalid UTF-16 selections. Older builds refuse the new schema. Migration keeps the previous raw generation unless obsolete tabs require post-commit pruning.

The controller snapshots and unmarks text before closing, cancels background status/dirty work, releases the closed text system, and immediately checkpoints. Reopening builds an editor from the snapshot with current preferences; it does not read the external file. File baselines/bookmarks remain intact unless the file is already open, when the reopened text becomes an unbound draft and a message explains Save As. Accepted Save tasks temporarily disable closing/reopening/reordering/clearing, preventing a late save binding from falling outside history. Normal Quit still drains Save. Open-tab undo managers survive reordering; closed tabs retain content and presentation but not undo stacks.

`TabBarView` retains native buttons across selection/dirty updates. Fixed-width truncated titles have full tooltips, position/unsaved accessibility labels, named close buttons and native focus rings. The horizontal strip reveals the selected tab; an All Tabs menu exposes the complete ordered list. Dragging uses public `NSDraggingSource`/`NSDraggingInfo` APIs, a generic document image and a private UUID-only drag pasteboard type. Drops are accepted only from the same strip, with insertion feedback and edge scrolling; no text or file authority leaves through tab dragging. Reordering changes array order without replacing the active editor or moving its selection.

Clearing/eviction drops values from the pending snapshot, then uses the ordinary serialized writer. Under the store lock, compare all tab identities in both verified generations with the incoming open/history identities. Publish the usual safe backup and complete new primary first. Only then, if an identity is no longer retained, atomically replace the backup with the new primary bytes. This handles coalesced close/clear operations even when a discarded tab was still open in the previous generation. Cleanup failure is reported, and retry (including the same revision) finishes it. A same-revision retry without cleanup synchronizes the directory before acknowledging success: a visible rename from an earlier failed attempt is insufficient evidence of durability. A crash before primary publication leaves prior history recoverable; after publication the newer primary is authoritative. Damage to that primary before interrupted cleanup is retried can still recover the older history, just as other fallback recovery can lose the newest operation.

Clear history is not secure erasure: damaged evidence, explicit exports, OS snapshots/backups and still-open versions remain. Damaged evidence is never deleted by normal pruning. The schema-6 manifest retains the same limit of 20 closed drafts. Measured many-large-tab memory remains a #12 release gate.

API signatures checked against the installed SDK; references: [Apple NSDraggingSource](https://developer.apple.com/documentation/appkit/nsdraggingsource), [Apple NSDraggingDestination](https://developer.apple.com/documentation/appkit/nsdraggingdestination).

## External file safety

Implemented in #6: `TextFileService` is an actor that balances security-scoped access, coordinates reads/replacements and captures device/inode plus SHA-256 baselines. Descriptor validation rejects special files and files over 100 MiB before coordination (which itself can block on a FIFO), and again before allocation/read. Reads check cancellation in 64 KiB chunks; the UI discards late cancelled results. Waiting inside OS file coordination is not instantly cancellable. Files over 20 MiB show a notice; layout and memory budgets remain #12 work.

Open/Finder requests queue behind recovery loading. A duplicate identity or canonical path selects the existing tab without replacing its recovered text or save baseline. Save captures immutable text before awaiting I/O; edits made during the write stay dirty. Debounced off-main digest comparison clears dirty state after undo restores exact saved bytes. Save As exposes encoding choice and preserves the chosen extension. Atomic writes update file metadata only after success, reject changed/deleted source baselines, and protect other open tabs. Failure keeps the draft and baseline. Quit cancels pending opens, dismisses file panels and drains an accepted save before the final private checkpoint.

File bindings persist format/identity/digests, a display location and an optional app-scoped bookmark. Stored paths grant no sandbox authority. Issue #7 resolves bookmarks lazily on explicit Save using `withSecurityScope`, `withoutUI` and `withoutMounting`, retains the returned URL object, balances successful start/stop calls and refreshes stale bookmarks while access is active. Location/permission refresh never accepts a new disk-content baseline. No external files or volumes are opened during workspace restoration. Legacy bindings require a new panel grant. Bookmark creation failure keeps a successful file save successful and shows a warning that access may need renewal after restart.

Native sheets offer Relink and Save As when resolving or reading a source fails. Relink accepts a user-selected file and updates permission/location without changing draft text, the saved content baseline or any external bytes. Another open tab cannot be used as a relink/save destination. A changed source opens a read-only preview (bounded to 64 KiB) with Cancel, Save As, Reload File and Overwrite File choices. Reload replaces the buffer with the reviewed full text through the editor undo manager; Undo restores the previous draft. Overwrite passes the reviewed file identity/digest through the same coordinated save guard; a second change blocks publication and requires another review. Unreadable content never offers blind overwrite. These comparisons protect against detected changes and cooperating coordinated writers, not an atomic compare-and-swap against every uncoordinated writer on every filesystem.

On open, record file identity and a digest of original bytes. Preserve decoded text exactly and track BOM/encoding/newlines separately. At save, coordinate access, compare current file content/identity to the baseline, and require an explicit conflict choice if changed. Atomic replacement in the same directory must retain correct sandbox authority and permissions. Error paths never clear dirty state. File/choice sheets permit application termination; Quit cancels their continuations, drains a publication already accepted, then checkpoints the final draft without a save confirmation. Recovered content is authoritative for dirty buffers; external files are not blindly reread on launch.

Support UTF-8 with/without BOM and BOM-marked UTF-16 LE/BE. Reject unsupported/invalid bytes rather than substituting U+FFFD. Preserve CRLF/LF/CR including mixed input. Encoding conversion is a user operation, never a side effect of display settings. File-size guard is checked before allocation; background loading is cancellable and does not mutate a tab until valid.

## Search, navigation and status

Issue #8 enables `NSTextView.usesFindBar` and incremental searching. AppKit owns the native Find/Replace bar, match traversal, case options, wraparound and replace operations through the existing per-tab undo manager. Menu commands target the selected editor explicitly, including when the Find field owns keyboard focus: Cmd+F, Cmd+Option+F, Cmd+G, Cmd+Shift+G and Cmd+E. AppKit's native Find operation uses the macOS Find pasteboard, separate from the general clipboard; it is not persisted in NoteHush recovery or logged. Search contents are never sent to a service. Native incremental Find may preview a match while its field owns focus; the status reports the document selection, which AppKit commits when Find is closed.

Cmd+L opens a validated Go to Line sheet. It uses logical lines and converts the selected line back to an AppKit UTF-16 offset without editing text. The shared sheet presenter permits termination; Quit cancels the sheet and checkpoints the draft. Navigation/file menu commands are unavailable while a sheet is attached or the workspace is read-only.

The active tab debounces analysis for 250 ms after editing, captures immutable text, and builds a `TextMetrics` index on a cancellable utility task. Switching away cancels pending work; revision and cancellation checks reject late results. Caret movement and selection changes query the completed index without rebuilding it. Checkpoints every 512 graphemes bound ordinary local scans; both sides of unusually long combining clusters are indexed so querying inside one does not scan it on the main thread. Columns and selected counts use extended grapheme clusters, while all editor/recovery offsets remain UTF-16. CRLF counts once; LF, CR, NEL, LS and PS are also logical line breaks. The status view shows an updating state until a matching revision is ready.

Index construction remains O(n) after a typing pause and retains an immutable text snapshot per analyzed tab. Index construction is separate from the immutable recovery and on-demand editor-layout paths; whole-app latency and memory still require measurement. `swift run -c release TextMetricsBenchmark` measures generated fixtures in isolation; M5 still owns whole-app latency, memory, energy and many-tab acceptance.

References reviewed 2026-09-06: [Apple NSTextFinder](https://developer.apple.com/documentation/appkit/nstextfinder), [incremental searching](https://developer.apple.com/documentation/appkit/nstextview/isincrementalsearchingenabled), [native Find options](https://support.apple.com/guide/textedit/find-and-replace-text-txtef6cfde1a/mac).

## Display preferences and printing

Issue #9 adds a workspace-wide `EditorPreferences` value. Defaults: system monospaced font at 14 pt, 100% zoom, system appearance, wrapping on and continuous spelling off. A PostScript font name records the selected face; an unavailable font falls back to system monospace. Presentation values clamp font size to 8–72 pt and zoom to 50–300%. Native AppKit settings controls list installed font families/faces only when Settings opens. Cmd+, opens Settings with explicit keyboard focus; View commands adjust zoom or wrapping.

Recovery schema 4 adds optional preferences and horizontal scroll displacement, reads schemas 1–4 and retains the previous raw generation on migration. Older builds refuse schema 4 rather than dropping settings. Missing preferences use defaults. No UserDefaults API or new required-reason privacy declaration is introduced; test workspaces isolate preferences with their drafts. Settings changes use the existing serialized checkpoint path, and Quit commits a pending valid font-size field edit before the final snapshot.

`EditorTab` changes presentation attributes directly without replacing text, changing the file binding or registering document undo. Font/zoom/wrap relayout preserves selection and a text scroll anchor. Wrapping configures native text-container tracking and horizontal scrolling; saved horizontal offsets clamp to valid bounds on restore. All tabs, including newly created and restored tabs, receive the preferences. Continuous spelling is optional; automatic correction, quote/dash substitution and text replacement remain disabled. Direct AppKit marked-text tests protect composition, while real keyboard/input-source coverage remains M5 work.

`WorkspacePrinter` lazily creates native printing objects. Page Setup is session-local and uses a copied `NSPrintInfo`; cancellation does not accept changes. Print captures the active tab, or its UTF-16 selection for Print Selection, into a separate `PrintDocumentView`. TextKit lays out full line fragments into page-sized containers and recomputes pages when paper/orientation/scaling changes. The chosen base font is used at 100% screen zoom, with black text on white paper and wrapping independent of the editor. Hardware imageable bounds and 36-point default margins constrain the page. An impossible page setup reports a nonmodal warning rather than silently truncating text. An empty document has one page.

Printing uses `NSPrintOperation` and the native sheet, including page range/preview and PDF output. No printer job or destination is persisted with the workspace. Sheet handling permits Quit and cancels pending sheets; already submitted jobs belong to the system print service. App Sandbox adds only `com.apple.security.print`, checked on the signed test app; app network permissions remain absent. PDF tests validate every line and word across page boundaries; actual physical printer output and signed distribution remain release checks.

References reviewed 2026-09-06: [Apple text view scrolling](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/TextUILayer/Tasks/TextInScrollView.html), [Apple pagination](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/Printing/osxp_pagination/osxp_pagination.html), [NSPrintOperation](https://developer.apple.com/documentation/appkit/nsprintoperation), [printing entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.print). API signatures were also checked against the installed macOS 26.6 SDK headers.

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

## Persistent file-access references

Implementation reviewed against Apple documentation on 2026-09-06:

- [App-scoped bookmark entitlement](https://developer.apple.com/documentation/professional-video-applications/enabling-security-scoped-bookmark-and-url-access)
- [Creating security-scoped bookmarks](https://developer.apple.com/documentation/foundation/nsurl/bookmarkcreationoptions/withsecurityscope)
- [Resolving without UI or mounting volumes](https://developer.apple.com/documentation/foundation/nsurl/bookmarkresolutionoptions/withoutui)
- [Starting scoped access](https://developer.apple.com/documentation/foundation/nsurl/startaccessingsecurityscopedresource())

## Lifecycle validation boundaries

The package-only recovery I/O observer lets the test executable stop at actual write/flush/rename boundaries. The app installs no observer, and no environment variable enables fault injection. SIGKILL validates process-crash consistency, not hardware power-loss durability. Debug and Release run the same 83 drills.

The `DebugUITesting` app has its own sandbox identity and requires a UUID workspace before startup. A host-only LaunchServices driver checks cold file events and recovery; distribution builds do not accept test overrides. Settings publishes local changes without refreshing unrelated controls during native action delivery, preventing an ending font edit from resetting a pending popup selection. External preference changes still refresh the panel.

## Interaction measurement boundary

The isolated `ReleasePerformance` app alone uses `PerformanceApplication` to signpost eligible native `sendEvent` dispatches. The override forwards the original event exactly once, performs no forced layout/display or full-text work, and publishes a numeric fixture completion marker only after the interval ends. The normal Release app retains `NSApplication` and excludes all probes. These app-processing durations exclude earlier event delivery and later deferred display; a separate XCTest clock measures the automation round trip. Neither is an event-to-visible acceptance result. See the [protocol, exact recovery oracles and current unverified native run](validation/2026-09-07-interaction-protocol.md).
