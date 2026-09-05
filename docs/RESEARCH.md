# Research: Windows Notepad and NoteHush

Research date: 2026-09-06. Primary sources only. This is a desk study, not hands-on testing of a Windows installation. Microsoft ships Notepad independently and uses staged Insider rollouts; an announcement does not establish availability on every Windows 11 machine.

## Findings and product decisions

| Capability | Evidence | NoteHush decision |
| --- | --- | --- |
| Multiple tabs, new/close tabs, tear-out windows, preference for opening tabs/windows | Microsoft introduced tabs in January 2023 [R1] | Tabs required in v1. One workspace window initially; dragging tabs into separate windows deferred. Keyboard switching and reordering required. |
| Session restoration without quit dialogs | August 2023 update restores open tabs and unsaved edits without saving original files [R2] | Required, always on in v1. Test clean quit, window close, forced termination, corruption, and denied storage. |
| Theme and fonts | 2021 redesign introduced dark/system appearance and font settings [R3] | Native light/dark/system appearance; family, face and size selection; display-only changes. |
| Find/replace and undo | 2021 redesign improved search and introduced multi-level undo [R3] | Native search/replace and per-tab undo/redo. Respect standard Mac commands. |
| Spell checking and autocorrection | March 2024 staged update introduced spelling support [R4] | Use macOS spelling support; optional. Disable automatic substitutions by default so code and plain text are not silently transformed. |
| Formatting and Markdown | May 2025 Insider announcement describes lightweight formatting [R5]; July 2026 release notes continue Markdown and nested-list fixes [R6] | Open .md as literal plain text. Rendering, rich text, tables, and embedded media deferred. |
| AI writing | Microsoft announced Write in May 2025 [R7] | Outside v1: does not serve offline startup speed and uncomplicated privacy. |
| Print, file formats and editing utilities | Microsoft support documents printing [R8]. Current release notes discuss print concurrency, launch, plain-text display and search edge cases [R6] | Printing, open/save, encoding/newline preservation, go to line, status, word wrap, zoom are in the v1 requirements; exact current Windows shortcuts/encoding defaults need hands-on comparison. |

### Research limitations

Font family/style/size controls and core file utilities are conventional editor requirements adopted for NoteHush; the consulted Microsoft sources do not establish every current control, encoding option, numerical file limit, or timing. Do not market untested feature parity. The July 2026 page describes Insider versions, not a stable-release baseline. Sources do not provide measured startup or typing budgets; NoteHush's budgets are independent targets.

## macOS adaptation

Use macOS menus, Cmd shortcuts, native panels, VoiceOver, focus behavior, and system typography. Avoid Windows visual assets, branding, icons, and exact UI imitation. The store title is NoteHush, with an original icon. A plain-text tool can provide meaningful utility through recovery, tabs, Unicode-safe editing and native integration; Apple's reviewer determines minimum-functionality compliance, not this document [A1].

`NSDocument` is a good starting point for conventional document apps [A2], but its lifecycle and autosave-in-place behavior do not directly express the requested private-draft workspace. Choose `NSApplication` + `NSWindowController` + `NSTextView`, with explicit save and independently persisted sessions. This trades framework-managed document behavior for explicit tests around lifecycle, file conflicts and sandbox bookmarks.

## Sources

- [R1 — Microsoft: tabs, 2023-01-19](https://blogs.windows.com/windows-insider/2023/01/19/tabs-in-notepad-begins-rolling-out-to-windows-insiders/)
- [R2 — Microsoft: session restoration, 2023-08-31](https://blogs.windows.com/windows-insider/2023/08/31/new-updates-for-snipping-tool-and-notepad-for-windows-insiders/)
- [R3 — Microsoft: redesign, fonts, theme, find and undo, 2021-12-07](https://blogs.windows.com/windows-insider/2021/12/07/redesigned-notepad-for-windows-11-begins-rolling-out-to-windows-insiders/)
- [R4 — Microsoft: spell checking, 2024-03-21](https://blogs.windows.com/windows-insider/2024/03/21/spellcheck-in-notepad-begins-rolling-out-to-windows-insiders/)
- [R5 — Microsoft: text formatting, 2025-05-30](https://blogs.windows.com/windows-insider/2025/05/30/text-formatting-in-notepad-begin-rolling-out-to-windows-insiders/)
- [R6 — Microsoft: Notepad release notes, updated 2026-07-24](https://learn.microsoft.com/en-us/windows-insider/release-notes/apps/notepad)
- [R7 — Microsoft: Write and other updates, 2025-05-22](https://blogs.windows.com/windows-insider/2025/05/22/paint-snipping-tool-and-notepad-updates-with-new-features-begin-rolling-out-to-windows-insiders/)
- [R8 — Microsoft: Help in Notepad](https://support.microsoft.com/en-US/Windows/Apps/help-in-notepad)
- [A1 — Apple: App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [A2 — Apple: NSDocument](https://developer.apple.com/documentation/appkit/nsdocument)
- [A3 — Apple: App Sandbox](https://developer.apple.com/documentation/security/app-sandbox)

Recheck Apple requirements at each release candidate. Update research when the proposed scope changes; do not silently expand v1 to every new Windows feature.
