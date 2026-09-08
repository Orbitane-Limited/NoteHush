# Integrated engineering validation, 2026-09-09

**Do not merge this validation branch into main.** It combines independent issue PRs only to expose integration failures before their normal CI/review/individual squash merges. It is not an approved release candidate.

Tested implementation commit: `5e0468d6a9ba70fd3b7ac36bb40212d055c3c6a0`. Included PR heads: #58 `74d7d97`, #59 `686cbaa`, #60 `068107e`, #61 `3cbf488`, #63 `7b3a5cd`, #65 `31c6980`, #66 `b94d8fa`, #70 `ad4a6cc`, #71 `c42a75c`. Integration retained all distinct changelog entries, both the automation prerequisite and failed-fixture preservation in performance scripts, and both new diagnostic/Privacy source entries in the project.

Executed on the M4 Pro Mac with Xcode 26.6 / Swift 6.3.3:

- 113 repository tests (64.716 seconds), 85 core tests (0.614 seconds), and 83 Debug plus 83 Release crash-recovery drills pass.
- Strict Swift formatting, configuration and relative links pass.
- Debug, all AppKit/UI test targets, universal arm64/x86_64 Release archive and isolated optimized test targets build. Exact product sandbox checks pass.
- The actual isolated app passes the complete original cold-launch/isolation/file-event/dirty-recovery/restart/independent-caret-and-scroll regression. The private host only adds failure retention and UUID recording; original assertions and observation bounds remain unchanged.
- A local automatic Xcode archive and App Store package export pass the committed strict verifier: both architectures, Apple chain/team and selected certificate pins, embedded Store profile, Hardened Runtime, product permissions, privacy/icon/version resources, no quarantine and no test/performance code. Version remains 0.1.0 (1).

Package SHA-256: `57887687d121f205aa5e6b42fe9fd38ec4be2c85c3743dc98b5a1758fb988b18`.

No package was installed/uploaded, credentials exported, tag created or release published. The source implementation is unmerged and its complete required native CI has not passed. This documentation commit changes no tested implementation files.

Remaining gates: native XCTest/CI and PR review/merges; mixed-script performance and empty RSS targets (#45/#67); supported OS/hardware and VoiceOver/IME acceptance (#13); authenticated App Store Connect record, processing and installed TestFlight (#14); verified public policy/support links, publisher-specific metadata and final screenshots (#15); release approval (#16).

The runner is online and idle. Its `notehush` routing label is temporarily held because Apple's read-only Automation Mode tool reports disabled/requires administrator authentication, and the latest native run timed out before UI cases. No macOS authorization was changed. Restoring the label and rerunning native CI requires that prerequisite and a valid exclusive-input window. Private build, cold-launch, signed-export and earlier failure evidence is retained locally; no failed timing sample or assertion was discarded.
