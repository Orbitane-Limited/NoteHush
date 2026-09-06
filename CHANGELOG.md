# Changelog

## Unreleased — 0.1.0 development

### Added

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
