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

Xcode 26.6 is the initial verified toolchain. Open `NoteHush.xcodeproj`, select the NoteHush scheme, and run. Debug uses a separate `.Development` bundle identifier. The current shell is a development preview; session recovery is implemented in M2.

```sh
bash scripts/check.sh
# Or run an individual check:
swift test
xcodebuild -project NoteHush.xcodeproj -scheme NoteHush -configuration Debug -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build
xcodebuild -project NoteHush.xcodeproj -scheme NoteHush -configuration Release -archivePath build/NoteHush-unsigned.xcarchive CODE_SIGNING_ALLOWED=NO archive
```

The project is committed so builds need only Xcode. When editing `project.yml`, regenerate using **XcodeGen 2.46.0** with `xcodegen generate` and commit both. Toolchain upgrades are explicit changes, not automatic switches to beta SDKs. Local running with the sandbox enabled requires a signing identity configured in Xcode; unsigned builds are for compile/CI verification.

GitHub CI runs the same checks on pull requests and main using this Mac's repository-scoped self-hosted runner. The Mac must be awake, online and logged in for jobs to run. See [runner operations](docs/SELF_HOSTED_RUNNER.md). The manually dispatched **Engineering delivery** workflow produces a clearly labeled unsigned archive plus checksum. Signed TestFlight delivery and GitHub production Releases are tracked in M6.
