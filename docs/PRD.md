# Product Requirements Document

Product: NoteHush. Target: v1.0.0 Mac App Store release. Initial engineering version: 0.1.0. Owner: CodeHubdotPk. Status: implementation baseline; release gates still open.

## Problem and audience

People moving between Windows and Mac need an immediately available plain-text scratchpad. They want multiple files and temporary thoughts in tabs, and they want to close the app without deciding where every draft belongs. NoteHush serves quick capture, editing small text/configuration files, lists, and temporary code snippets.

## Scope and assumptions

Swift 6; native AppKit; macOS 14 and newer; universal arm64/x86_64 builds. English UI initially with localizable strings and full Unicode input. Single workspace window for v1. Offline by design. No login, ads, analytics, network entitlement, third-party runtime SDK, AI, sync, rich text, extension system, or in-app purchase. Pricing, distribution territories, publisher identity and final icon remain release-time product decisions. These exclusions keep v1 bounded; they are not claims about future versions.

## Functional requirements

| ID | Requirement and acceptance |
| --- | --- |
| NH-01 | Create tabs via Cmd+N or +; select, reorder, close, switch with keyboard. Display useful title and unsaved state. No arbitrary small tab-count cap. |
| NH-02 | Cmd+Q and red window close never ask whether to save unsaved files. Close the only workspace terminates the app. Restore the workspace on next launch. Closing a tab is separate: retain it in a bounded recently-closed list and offer Reopen Closed Tab; no destructive dismissal prompt. |
| NH-03 | Recover untitled drafts, dirty edits to named files, tab order, active tab, UTF-16 selection, scroll anchor, font/wrap preferences and window bounds. Clamp invalid geometry/ranges. Recovery never overwrites the original file. |
| NH-04 | Continuous debounced checkpoints while typing; flush immediately on tab operations and orderly shutdown. Force-kill recovery has an explicit target of at most 500 ms of uncheckpointed input on a healthy local disk. Never promise zero loss under power failure, disk exhaustion, or OS kill. |
| NH-05 | Recovery write failures show a persistent nonmodal banner and Retry/Export action. Quitting still follows NH-02. Startup corruption preserves source artifacts, recovers the latest valid generation, and reports the fallback. Unknown schema versions open read-only recovery mode without overwriting newer data. |
| NH-06 | Open multiple user-selected plain-text files and Finder Open With requests. Reopening the same file selects its existing tab. Use sandbox permissions and persistent bookmarks; a revoked bookmark offers relink or Save As while keeping draft text. |
| NH-07 | Explicit Save and Save As, standard panels and shortcuts. UTF-8 default, UTF-8 BOM and BOM-marked UTF-16 LE/BE support. Preserve supported source encoding and mixed newlines unless the user requests conversion. Invalid/binary input reports an error; never use lossy decoding. |
| NH-08 | Detect external modifications before overwriting. Offer inspect/reload, Save As, or explicit overwrite only during a save operation. Atomic coordinated writes. Failed writes keep the dirty buffer and recovery copy. |
| NH-09 | Native cut/copy/paste/select all and per-tab undo/redo. Plain-text paste. Unicode, emoji, RTL and IME composition work. Automatic quote/dash/text replacement disabled by default. |
| NH-10 | Find next/previous and replace one/all with case option and wrap; go to line; status shows line/column, selection/character counts, encoding and newline style. UI remains responsive for large files. |
| NH-11 | Workspace-wide font family/face/size, word wrap, zoom/reset, light/dark/system appearance. Preferences survive restart and never alter text bytes. Optional spell checking. Native print/page setup. Print the active tab or selected text at base font size, wrapped to paper with black text on white; screen zoom/wrap do not change output. |
| NH-12 | Keyboard-operable tabs, named accessibility controls, visible focus, sufficient contrast, reduced-motion support. Follow native system interactions and editable text semantics. |
| NH-13 | Privacy policy and support accessible from app/store listing. No developer data collection; local recovery storage is explained. Never send notes in logs, crash attachments, or support requests automatically. |

## Persistence behavior matrix

NH-10 counting semantics: characters and columns use extended grapheme clusters (an emoji or composed character counts once), including whitespace and line breaks. CRLF counts as one character and one logical line break. Recognize LF, CR, CRLF, NEL, line separator and paragraph separator; wrapping does not create logical lines. Line/column describe the start of the selection, use one-based numbering, and an empty document has line 1/column 1. The status counts characters touched by a nonempty selection; encoding describes the current file binding (UTF-8 for an untitled draft). Mixed endings remain unchanged. Show an updating state instead of stale counts while background analysis is pending.

| Event | User-visible behavior | Disk effect |
| --- | --- | --- |
| Typing | Immediate editing | Schedule private checkpoint, no original-file write |
| Save | Native destination if needed | Coordinated write to user file plus recovery metadata |
| Close tab | Remove tab; Reopen Closed Tab available | Retain up to 20 recently closed tabs, with clear-history control |
| Close window / Quit | Exit with no save confirmation | Flush changed tabs + workspace metadata |
| Force kill | No cleanup possible | Restore last valid committed checkpoint |
| File moved/deleted externally | Draft remains editable | Relink/Save As; never silently recreate deleted source |
| Disk full/denied | Nonmodal recovery warning | Preserve previous checkpoint; record failure state without text logs |

Tab commands: Cmd+W closes the active tab; Cmd+Shift+W or the red window control closes the workspace and quits. Cmd+W in Settings closes Settings. Closing the last tab creates one empty tab. Cmd+Shift+T reopens the newest closed tab at its former position (clamped to the current tab count). Closing a background tab keeps the active tab; closing the active tab selects the next tab, or the previous one at the end. The File menu explicitly clears recent history. History holds snapshots for up to 20 tabs, including selection, scroll and file metadata; undo stacks end when a tab closes. If that file is already open when its closed version is reopened, preserve the closed text as a separate unbound draft for Save As. Never replace either buffer.

Drag a tab title to reorder it; Window → Move Tab Left/Right also provides Cmd+Control+Shift+[ / ]. Ctrl+Tab and Ctrl+Shift+Tab switch tabs, while the All Tabs button or Cmd+Option+Shift+T exposes every tab in a native menu. Selected tabs scroll into view. Tab management waits for an accepted Save to finish so closed history includes its final binding and any later edits; Quit continues to drain accepted saves without a confirmation.

## Performance targets

Measure optimized builds on a recorded baseline (minimum M1/8 GB, macOS 14 or later, local SSD). Use medians and p95 over at least 20 runs; budgets are targets until measured.

| Scenario | Release target |
| --- | --- |
| Cold launch, empty workspace | p95 <= 500 ms to editor accepting input |
| Restore 20 tabs totaling 5 MiB | p95 <= 1 second to selected tab accepting input |
| Typing, 1 MiB text | p95 event-to-visible-edit <= 16.7 ms, no recovery serialization on main thread |
| Switch loaded tabs | p95 <= 50 ms |
| Open 10 MiB UTF-8 text | p95 <= 1 second, interactive window during load |
| Idle memory, empty/20 x 256 KiB tabs | <= 80 / 150 MiB resident footprint target |
| Idle CPU | < 1% average across 60 seconds after recovery settles |

Files over 20 MiB enter an explicit large-file path. Initial v1 safeguard: reject files above 100 MiB before loading, explain the limit, and keep existing work untouched. Any supported limit must be documented in the listing. Raise limits only with evidence. No performance marketing claim before measurements.

## Release acceptance

All v1 requirements traced to closed issues and tests; no known data-loss bug; migration and corruption drills pass; supported-OS/architecture and accessibility evidence recorded; signed archive validated; TestFlight tested; privacy/support URLs public; metadata accurate; current Apple requirements reviewed. App Review approval is an external outcome, not something this PRD guarantees.
