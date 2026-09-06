# NoteHush

A fast, native macOS notepad written in Swift. Open a tab, write, close the app, and continue where you left off.

**Status:** pre-release development, starting at `0.1.0`. Not yet ready for App Store submission. The repository is private; no open-source license has been granted.

## Product contract

- Plain text with tabs and native Mac keyboard commands.
- No save-confirmation dialog when closing the window or quitting.
- Restore tabs and unsaved edits from a private local recovery store.
- Save / Save As explicitly writes a document to the user's chosen location.
- Offline operation, no accounts, advertising, telemetry, or runtime dependencies.
- Swift 6, AppKit text editing, macOS 14+, Apple silicon and Intel builds.

## Documentation

- [Research](docs/RESEARCH.md)
- [Product requirements](docs/PRD.md)
- [Technical design](docs/TECHNICAL_DESIGN.md)
- [Implementation plan](docs/IMPLEMENTATION_PLAN.md)
- [Testing strategy](TESTING.md)
- [App Store readiness](docs/APP_STORE.md)
- [Release process](docs/RELEASING.md)
- [Contributor workflow](CONTRIBUTING.md)
- [AI context](AGENTS.md)
- [Changelog](CHANGELOG.md)

Track delivery in [milestones](https://github.com/CodeHubdotPk/NoteHush/milestones) and [issues](https://github.com/CodeHubdotPk/NoteHush/issues). Each issue uses a separate branch and pull request; `main` is the integration branch.

## Development

Xcode 26.6 is the initial verified toolchain. Open `NoteHush.xcodeproj`, select the NoteHush scheme, and run. Debug uses a separate `.Development` bundle identifier. Tabs, independent undo, continuous recovery, prompt-free quit/relaunch, native Open/Save/Save As and Finder file opening are implemented. Persistent file permissions, relinking, conflict previews and undoable reloads are also implemented. Native Find/Replace, Go to Line, Unicode-aware status counts, display preferences and printing are implemented. Tab closing/reordering and release polish remain on the roadmap.

File operations preserve UTF-8, UTF-8 BOM, BOM-marked UTF-16 LE/BE and mixed CRLF/LF/CR newlines. Invalid encoding, binary controls, special files and files above 100 MiB are rejected; files above 20 MiB show a large-file notice. Explicit saves refuse changed/deleted sources and destinations open in another tab. After relaunch, recovered text remains authoritative. Save resolves a private security-scoped bookmark, follows moved files when macOS can locate them, and offers Relink or Save As for unavailable files. External changes show a preview with Cancel, Save As, Reload and Overwrite choices; overwrite rechecks the reviewed disk version. Quitting dismisses these sheets and preserves the draft. Whole-app performance budgets remain unverified.

Find uses Cmd+F; Find and Replace uses Cmd+Option+F. Cmd+G / Cmd+Shift+G navigate matches, Cmd+E uses the selection for Find, and Cmd+L goes to a logical line. The native Find options include Ignore Case. Status counts emoji and combined characters once, reports the start of the selection, and preserves mixed newline styles. Counts update in the background after typing pauses.

Settings (Cmd+,) chooses a font family/face/size, system/light/dark appearance, word wrap, zoom and optional spelling for all tabs. Defaults are system monospace 14 pt, 100% zoom, system appearance, wrap on and spelling off. View offers Zoom In (Cmd+=), Zoom Out (Cmd+-), Actual Size (Cmd+0) and Word Wrap. Preferences restore with the workspace; presentation never changes text bytes or file encoding. Automatic quote/dash replacement and spelling correction remain off.

Print (Cmd+P) prints the active tab; File > Print Selection prints only selected text. Page Setup chooses paper, orientation and scaling for the current session. Printing wraps to the paper using the base font size with black text on white paper; screen zoom and wrap do not affect output. Native Print includes PDF output. A print job uses a snapshot, so editing remains separate from printing.

```sh
bash scripts/check.sh
# Or run an individual check:
swift test
bash scripts/test_app.sh
python3 scripts/test_crash_recovery.py
xcodebuild -project NoteHush.xcodeproj -scheme NoteHush -configuration Debug -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build
xcodebuild -project NoteHush.xcodeproj -scheme NoteHush -configuration Release -archivePath build/NoteHush-unsigned.xcarchive CODE_SIGNING_ALLOWED=NO archive
```

The project is committed so builds need only Xcode. When editing `project.yml`, regenerate using **XcodeGen 2.46.0** with `xcodegen generate` and commit both. Toolchain upgrades are explicit changes, not automatic switches to beta SDKs. UI tests use ad-hoc local signing with App Sandbox enabled and isolated UUID workspaces. Production signing and hardened-runtime validation remain release gates; unsigned archives are for compile/CI verification.

GitHub CI runs the same checks on pull requests and main using this Mac's repository-scoped self-hosted runner. The Mac must be awake, online and logged in for jobs to run. See [runner operations](docs/SELF_HOSTED_RUNNER.md). The manually dispatched **Engineering delivery** workflow produces a clearly labeled unsigned archive plus checksum. Signed TestFlight delivery and GitHub production Releases are tracked in M6.
