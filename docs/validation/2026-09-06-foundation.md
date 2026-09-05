# Foundation validation — 2026-09-06

Scope: issue #2, native scaffold. Xcode 26.6 (17F113), Swift 6.3.3, Apple silicon host. Source changes are reviewed in the issue #2 PR.

| Check | Result |
| --- | --- |
| `swift test` | 5 XCTest cases passed: model invariants, exact Unicode/CRLF round trip, UTF-16 range validation and overflow-safe clamping |
| `xcrun swift-format lint --strict --recursive App Sources Tests Package.swift` | Passed |
| `plutil -lint` entitlements, Info.plist and privacy manifest | Passed |
| Debug `xcodebuild ... CODE_SIGNING_ALLOWED=NO build` | Passed |
| Release `xcodebuild ... CODE_SIGNING_ALLOWED=NO archive` | Passed |
| `lipo -archs` archived executable | arm64 and x86_64 |
| Archive Info.plist/resources | Version 0.1.0, build 1, minimum macOS 14.0, privacy manifest included |

The AppIntents metadata tool emits its standard no-AppIntents-dependency warning; the app intentionally has no AppIntents integration. Unsigned validation disables runtime signing enforcement; this does not validate distribution signing or actual sandbox access. Both architecture slices were compiled, but Intel runtime and minimum-OS tests were not run. UI automation, persistence, benchmarks and App Store validation belong to later milestones. The current preview explicitly warns that drafts are not restored yet.
