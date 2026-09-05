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

The foundation milestone adds the Xcode project and exact build commands. Xcode 26.6 is the initial verified toolchain; XcodeGen 2.46.0 generates the committed project. Toolchain upgrades are explicit changes, not automatic switches to beta SDKs.
