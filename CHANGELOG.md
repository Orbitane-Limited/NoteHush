# Changelog

## Unreleased — 0.1.0 development

### Added

- Opt-in native typing/tab-switch measurement protocol with separate app-dispatch and automation timing, strict sample extraction and exact recovery oracles; native validation remains pending.
- Original NoteHush app icon with all macOS asset sizes, audited export metadata, and draft Store/privacy/support materials. Publisher confirmation, public hosting, in-app policy links and final screenshots remain release gates.

- Product research, requirements, technical design, testing and App Store release plan.
- Milestone-based GitHub delivery process.
- Swift 6 AppKit development shell, Foundation core model and Unicode-safe validation tests.
- Version 0.1.0/build 1, macOS 14 target, sandbox configuration and universal Release settings.
- GitHub PR/main validation and manually dispatched unsigned archive delivery with checksums.
- Versioned atomic recovery checkpoints with integrity checks, backup fallback, exclusive writer locks and failure/concurrency tests.
- Native tabs with independent text storage/undo, keyboard switching, automatic draft checkpoints, and prompt-free quit/window-close restoration of tabs, selection, scroll and window bounds.
- Persistent recovery warnings with retry and JSON export; unreadable/newer workspaces remain protected from editing and replacement.
- Deterministic checkpoint/quit race tests, AppKit integration tests, sandboxed UI relaunch tests and child-process SIGKILL recovery drills in CI.
- Native multi-file Open, Finder requests, Save and Save As with encoding selection and duplicate-file detection.
- Lossless UTF-8/BOM and UTF-16 LE/BE handling, mixed-newline preservation, cancellable background reads and atomic coordinated writes with changed-file safeguards.
- Dirty-file recovery metadata with schema-1 migration, failed-save and concurrent-edit protection, and bounded file loading.

- Persistent app-scoped file bookmarks with lazy resolution, moved-file access, stale refresh and schema-3 recovery migration.
- Relink/Save As for missing or inaccessible files, disk-version conflict previews, undoable reloads and explicit overwrite guarded against further external changes.
- Quit dismisses conflict/relink sheets without saving or losing the recovered draft.
- Native Find/Replace with case options, next/previous matches, standard shortcuts and per-tab undo.
- Go to Line and a status bar with Unicode character/selection counts, logical line/column, encoding and newline information; cancellable background counting avoids rescanning during caret movement.

- Native Settings with font family/face/size, appearance, wrapping, zoom and optional spelling shared by all tabs and restored with schema-4 recovery; unwrapped horizontal scroll also restores.
- Zoom shortcuts and reset, unchanged text/encoding/undo during display changes, and marked-text composition preservation.
- Native Page Setup, Print and Print Selection using independent paginated snapshots at base font size, with PDF output and sandbox printing entitlement.

- Pointer and keyboard tab reordering with stable editor selection, accessible close controls and an All Tabs overflow menu.
- Cmd+W tab closure, Cmd+Shift+T recovery of the 20 newest closed drafts, explicit history clearing, and schema-5 post-commit backup pruning. Closing the last tab leaves an empty scratchpad; red window close and Quit still restore the workspace.

No production release has been published.

### Fixed

- Xcode project regeneration preserves the existing audited encryption declaration.

- Defer native scrollbar auto-hiding until tab presentation so legacy scrollbars do not typeset the first paragraph of every hidden restored draft.

- Restore the selected viewport before keyboard focus to reduce initial mixed-script layout work while preserving offscreen caret positions.

- Restored hidden tabs avoid eager bidirectional typesetting; the selected editor uses native anchor scrolling with on-demand layout.

- Recovery schema 6 stores immutable tab text with small atomic manifests, preserves legacy generations and damaged evidence, and avoids rewriting unchanged tabs.

- Continuous-input checkpoint timer crash exposed by the linked Swift test harness; scheduling intervals remain unchanged.
- Same-revision recovery retries now verify directory synchronization before acknowledging a previously renamed checkpoint.
- Committing a font-size field no longer resets a pending Appearance or Zoom menu choice.

### Validation

- Complete four-workload interaction baseline with 160 retained native-dispatch/automation observations and exact recovery checks; mixed-script performance and release budgets remain open.
- Native folder-panel tests check the complete generated path and avoid redundant click/Select All setup before keyboard entry.
- Require disk headroom before self-hosted native checks and performance work, with retained capacity reports and failure-path tests after confirmed macOS cache-cleanup kills of the UI runner.

- Optimized, isolated first-frame/editor-readiness measurements with a complete 20-sample baseline and app-only profiling; product performance budgets remain open.
- Declare and validate the approved app-container file-metadata reason used by recovery fingerprints, alongside the existing user-selected-file reason.
- Use the existing Finder opening path for the two long file-access cases' initial fixture setup, with exact app/process checks; native panel coverage, all assertions and time allowances remain unchanged.
- Isolated 20-sample Release recovery benchmark with raw latency and logical I/O measurements for 5 MiB and 30 MiB workspaces; whole-app performance remains unverified.
- 83 force-kill scenarios in both Debug and Release, covering real manifest/blob publication phases, continuous input, legacy migration, damaged evidence and closed-history reclamation.
- Isolated cold LaunchServices tests with a dedicated sandboxed test app; missing or malformed test workspace IDs stop startup.
- App recovery-warning/Retry tests and native Print/Page Setup cancellation followed by red-window closure.
- Repository bootstrap resolves the canonical GitHub owner, reads every result page and defaults to a read-only preview; offline tests protect existing issue bodies and prevent mutations after failed preflight reads.
