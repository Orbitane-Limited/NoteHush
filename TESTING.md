# Testing Strategy

Tests protect user data and measure behavior. Passing a build is not proof of data recovery, performance, accessibility or App Store readiness. Record executed commands, toolchain, commit and hardware with results.

## Layers

| Layer | Required coverage | Where |
| --- | --- | --- |
| Unit | Unicode/range validation, text formats, model invariants, revisions | Core XCTest suite |
| Persistence integration | atomic checkpoints, stale writes, corruption, fallback, unknown schema, denied writes, migration, repeated loads | temporary-directory core tests |
| File integration | encoding round trips, mixed newlines, conflicts, failed saves, bookmark relink, file coordination | app integration target and sandbox fixtures |
| UI | tabs, editing, independent undo, clean quit/relaunch, close-window/relaunch, find, fonts, keyboard and file panels | isolated XCUITest workspace |
| Crash drill | SIGKILL during write and continuous input, last acknowledged checkpoint restoration | child-process harness + manual signed build |
| Performance | startup, restore, typing, tab switch, memory, energy, large files | optimized build + Instruments/signposts |
| Distribution | sandbox access, signing, privacy resources, universal binary, archive validation | CI artifact inspection + TestFlight |

## Critical scenarios

1. Create three untitled tabs including emoji, combining marks and Urdu. Edit a named file. Select the middle tab, select text, scroll, resize, quit immediately after typing. Relaunch: content/order/selection/scroll/frame restored, source file unchanged, no save prompt.
2. Close via red window button and repeat. Close an individual unsaved tab and reopen it. Test bounded recently-closed history and explicit clearing.
3. Kill a helper process before/during/after an atomic checkpoint. Restore the last committed version; never accept half a workspace. Measure actual possible lost-input interval.
4. Truncate primary, corrupt checksum, remove a referenced blob, duplicate tab IDs, use an unknown schema. Verify fallback or read-only warning and preservation of original evidence.
5. Inject write, rename and permission errors (do not fill the user's actual disk). Verify nonmodal warning, preserved dirty state, retry, explicit export, and no false success.
6. Rename/delete/revoke access to a source file. Externally modify it after open. Save must not overwrite without conflict handling; Save As keeps text.
7. Round-trip UTF-8/BOM, UTF-16 LE/BE, CRLF/LF/CR/mixed, trailing newlines, emoji and RTL. Reject malformed UTF-8, odd UTF-16, binary content and oversized files.
8. Type with Japanese/Chinese IME, Urdu RTL, dead keys and emoji; undo after tab switching. No marked-text truncation, cross-tab undo, smart-quote substitution or wrong selection offsets.

## Required checks by change

- Docs: relative-link validation and traceability review.
- Core: `swift test`, Swift formatting, recovery integration tests.
- App: core checks + unsigned Debug build and Release archive; relevant UI cases when target exists.
- Persistence/lifecycle: all recovery tests + clean quit/relaunch + kill drill; corruption/future-schema regression.
- Release: all layers; archive validation and real TestFlight installation. Runtime test macOS 14 and current stable macOS; Apple silicon and an Intel Mac if Intel is advertised. Cross-compilation alone is insufficient.

Run `bash scripts/check.sh` for formatting, configuration, core tests, six SIGKILL drills, AppKit integration tests, sandboxed XCUITests, Debug build and universal Release archive verification. Logs and `.xcresult` bundles are written to `build/logs/`; GitHub CI retains them as artifacts. `bash scripts/test_app.sh` repeats the app tests; `python3 scripts/test_crash_recovery.py` repeats the crash drills; `bash scripts/archive.sh` repeats archive validation.

App tests require an awake, unlocked GUI login on the runner and use ad-hoc local signing. The test script verifies the built app's sandbox entitlement. Ad-hoc signing disables hardened-runtime enforcement in Xcode; production signing/runtime validation remains a separate M6 gate. AppKit integration tests compile the same editor/window sources in a test bundle and inject unique temporary recovery directories. XCUITests launch the development bundle with `NOTEHUSH_TEST_WORKSPACE=<UUID>`; Debug accepts only a valid UUID and uses `Application Support/NoteHush/UITests/<UUID>` within its own sandbox. Release has no environment override. Fixtures are never reset into normal recovery storage and do not contain user notes.

Run the complete UI suite through `scripts/test_app.sh`: Xcode also sandboxes its UI runner, so the host script creates a disposable APFS image, runs the mounted-file scenario with the other tests, detaches the image, then runs the offline-restoration scenario against the same isolated workspace. Direct Xcode runs skip these two tests if no host fixture exists; the CI script requires both scenarios to actually pass, so a missing fixture cannot silently weaken CI. The fixture script only removes its generated UUID directory, detaches before deletion and cleans up on shell exit/interrupt. A per-checkout lock prevents overlapping fixture runs. If a terminated run leaves a fixture behind, confirm no test run is active, inspect it and use `python3 scripts/volume_fixture.py cleanup` before rerunning; never point the helper at an existing user volume.

The checkpoint scheduler uses an injected clock and gated writer to exercise a cancelled debounce, continuous typing, immediate shutdown, repeated shutdown and a final snapshot queued behind slow I/O. The child harness validates complete text and never loses an acknowledged checkpoint across six interruption timings. These drills do not measure a worst-case 500 ms lost-input bound under every disk/OS condition. Tests use unique temporary roots; never make test flags capable of deleting normal user data or add sleeps to hide races.

File tests round-trip exact bytes across supported encodings, literal BOM characters, mixed newlines, emoji, RTL and long lines. They reject malformed encodings, binary controls, sparse oversized files, FIFOs and directories; exercise external changes/deletion, symlink/hard-link identity, cancelled reads and failed publication. Gated AppKit tests cover late cancelled results, dirty file recovery and typing during Save followed by undo back to saved bytes. UI tests exercise actual sandboxed Open/Save As panels, cancellation and a LaunchServices file request into an isolated running workspace. Injected bookmark tests cover stale refresh, balanced access, revoked authority, resolution/creation failures, legacy bindings, schema-2 migration and an external edit after overwrite approval. AppKit tests verify relink preserves the draft/baseline and Reload can undo back to the draft. Sandboxed UI tests cover moved files after restart, bookmark renewal after atomic Save, denied file permissions, delete/relink/Save As, conflict preview/reload/undo, repeated overwrite review, and Quit during a conflict. A disposable APFS disk image exercises mounted-volume Save and offline restoration without automatic mounting; it never targets an existing user volume. These locally signed tests do not replace production signing, physical removable-drive, TCC-specific Desktop/Documents, or compatibility release gates.

Search/navigation tests cover native Find options and replacement, undo isolation, logical line jumps, status updates, no matches and quit with the navigation sheet open. Core tests compare sparse Unicode indexing with an independent linear oracle, including partial UTF-16 selections, mixed endings and a 100,000-mark combining cluster. Gated AppKit tests reject stale/cancelled analyses and verify that caret movement does not rebuild the index. Find tests preserve and restore the macOS Find pasteboard without logging its prior contents; the general clipboard is untouched. Capture only the NoteHush window, never the whole application screenshot on macOS.

LaunchServices calls from the sandboxed UI runner did not reliably forward the workspace environment; command-line overrides are also ignored for sandboxed callers. File request tests now launch through XCTest first, then send the request to that exact running installation and assert its isolated two-tab state. Earlier cold-launch evidence does not establish test isolation. Cold Finder launch remains a manual/host-driven release check; never run it from the sandboxed test runner against normal recovery storage.

Preferences tests cover schema-3 migration preserving the raw previous generation, bounded display values, zoom stops, all-tab/relaunch inheritance, exact UTF-16 file bytes, bindings and undo preservation, marked-text composition, unavailable fonts, and unwrapped horizontal scroll restoration. Native UI tests exercise font family/face/size, appearance, spelling, wrapping, zoom/reset shortcuts, Cmd+, and keyboard font selection, plus quitting while Settings has an uncommitted size field or native Print/Page Setup is open. Print tests capture the active tab or its Unicode selection and produce a multi-page PDF; PDFKit verifies every marker and whitespace-normalized word exactly once, paper dimensions, changed orientation/scaling, empty output and impossible page settings. The generated PDF is retained as a test attachment. Physical printers, installed-font removal between launches and real Japanese/Chinese input-source interaction remain manual checks. A direct `setMarkedText` test does not certify every IME.

Tab-management tests cover schema-4 migration, history validation, clearing/eviction after primary publication, coalesced close/clear, failed primary and failed cleanup writes, and same-revision retry. AppKit cases close more than 20 tabs, reopen and clear across restarts, preserve file baselines/Unicode/selection/scroll, protect duplicate open files and edits during accepted Save, and inspect named controls/visible selected tabs with 100 tabs at the minimum width. Native UI cases drag and reorder by shortcut, restore order, close/reopen the last tab, clear history and navigate overflow. Existing Settings and red-window/Quit cases protect Cmd+W routing. These checks do not certify VoiceOver, minimum-OS/Intel runtime or many-large-tab performance; those remain M5 gates.

## Performance protocol

Use PRD budgets, Release optimization, no debugger. Record hardware, OS, power state, file sizes, character distributions and cache conditions. Run >=20 repetitions and report median/p95. Use a mix of 1 KiB, 1 MiB, 10 MiB and 100 MiB files, a long unbroken line, 100+ tabs, RTL, CRLF and Unicode. Distinguish process launch from first editable frame. Use Instruments Time Profiler, Allocations and Energy; verify no serialization on the main thread. Flaky shared-runner wall-time tests are informational; reproducible reference-hardware regressions gate release.

`swift run -c release TextMetricsBenchmark` runs 20 repetitions per generated 1 KiB, 1 MiB, 10 MiB and 100 MiB fixture, including mixed Unicode/CRLF and an unbroken line. It reports median/p95 index construction and batches of caret/selection/line queries. This is an informational microbenchmark; it does not measure app startup, typing latency, native Find, RSS or energy, and does not close M5 performance gates.

## Manual acceptance and evidence

- VoiceOver navigation and tab names; full keyboard access, focus, contrast, reduced motion; 200% text size.
- Multiple monitors/disconnected display, dark/light appearance, minimum window dimensions.
- Fresh installation, upgrade, corrupted store, disk denied, logout, Force Quit and reopen.
- Signed sandboxed file open/save across Desktop, Documents, external drive and unavailable volume.
- Store privacy answers match app behavior; no outgoing network activity; no draft text in logs.

Store dated evidence under `docs/validation/` with commit/build numbers, commands, pass/fail and limitations. Redact user data. Do not check the manual boxes based on code review alone. A release-blocking data-loss defect stays open regardless of code coverage percentage.
