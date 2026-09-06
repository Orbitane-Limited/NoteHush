# NoteHush agent context

Read `docs/PRD.md`, `docs/TECHNICAL_DESIGN.md`, and `TESTING.md` before changing behavior. This file is the shared context for all coding assistants; do not create conflicting instructions in CLAUDE.md.

## Non-negotiable behavior

1. Swift-native macOS app. No Electron, web editor, cloud service, account requirement, or analytics SDK.
2. Tabs are first-class. Window close and Quit never show an unsaved-file confirmation. Private session checkpoints are separate from explicit file saves.
3. Preserve unsaved text, tab order, selected tab, caret/selection, scroll, and window geometry across a normal restart. Never reload the external file over a recovered dirty buffer.
4. Never silently discard malformed recovery data, overwrite an externally changed file, replace undecodable bytes, or claim successful persistence after a failed write.
5. Keep App Sandbox enabled. For files, request only user-selected read/write access and app-scoped bookmarks. User-initiated printing uses the narrow printing entitlement. Do not request Full Disk Access.
6. Text stays local. Never log user text, paths, bookmarks, or clipboard contents. UI automation uses isolated fixtures.

## Structure and implementation

- `App/NoteHush`: AppKit composition root, windows, editor, preferences, file coordination.
- `Sources/NoteHushCore`: Foundation-only models, recovery, encoding and testable logic.
- `Tests/NoteHushCoreTests`: core tests; `Tests/NoteHushUITests`: isolated UI scenarios.
- `Config`: entitlements, version settings; `App/NoteHush/Resources`: privacy manifest/assets.
- `scripts`: repeatable checks; `.github/workflows`: CI and delivery.
- Swift 6 strict concurrency; UI is main-actor isolated. Serialize recovery I/O off the UI thread. Avoid unchecked Sendable and force unwraps unless an invariant is documented and tested.
- Prefer small concrete types. Introduce protocols at failure-injection boundaries, not for every class. Use public Apple APIs and no third-party runtime dependencies initially.
- Preserve Unicode and original supported encoding/newlines. Treat AppKit selection offsets as UTF-16 offsets, not Swift character counts.
- Keep typing incremental; do not serialize every tab or recompute the whole document on each keystroke.

## GitHub workflow

- Select an open issue in milestone order; read its dependency and acceptance criteria.
- Branch `issue-<number>/<short-description>` from current main. One issue per PR. Include `Closes #<number>` and actual validation results.
- Do not bundle unrelated fixes. Update docs/changelog when behavior changes.
- Run the required checks. Inspect failures; never bypass failing checks or weaken assertions to get green CI.
- Squash merge only after checks pass and review is resolved. Use a human reviewer when available; do not invent independent review or self-approve. The empty initial main commit is the only bootstrap exception to PR-based changes.
- Do not force push main, publish a release with unresolved release gates, or commit signing credentials.
- Do not spawn sub-agents unless the user explicitly requests delegation.

## Definition of done

Acceptance criteria met; build succeeds with sandbox entitlements; relevant tests pass; accessibility/performance impact considered; recovery and privacy behavior preserved; docs and issue status accurate. An unsigned archive or passing unit tests alone never means App Store ready. Mark unverified hardware, signing, and manual tests as unverified.
