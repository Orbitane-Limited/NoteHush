# Integrated engineering validation, 2026-09-09

**Do not merge this validation branch into main.** It combines independent issue PRs to expose integration failures before their required CI/review/individual squash merges. It is not an approved release candidate.

## Latest ten-PR candidate

Subsequent host-only integration at `30a7b7e` adds PR #74's large-file protocol. The [complete before/after comparison](2026-09-09-large-file-opening-comparison.md) passes all 40 observations per build: mixed-script request-to-checkpoint p95 falls from 9,654.208 to 349.982 ms, while ASCII p95 increases from 414.136 to 586.623 ms and all outliers remain retained. All 125 integrated repository tests/88 Swift tests and the original native shared-reader cold/recovery regression pass. App/core/configuration source is unchanged from `9557aec`. A separate long-paragraph diagnostic still fails on both main and candidate and is tracked in #75; physical responsiveness and full UI/release gates remain open.

Clean tested implementation: `9557aecfdd7fed533cdf7fb2553b0f62aa866cb8`. It includes the nine earlier PRs below plus #72 at `8bc1692` for native TextKit 2 paragraph presentation, viewport restoration and Undo/teardown corrections. Integration retained the explicit input-policy settings, Privacy/diagnostic/presenter project sources and each changelog entry. Main remains `bb49b49`; version remains **0.1.0 (1)**.

[Complete numeric results and artifact provenance](2026-09-09-integrated-paragraph-candidate.json) record these separate checks:

- All **113 repository tests, 85 core tests and 166 Debug/Release crash drills** pass. Strict Swift formatting, configuration and links pass; Debug, universal Release archive and optimized application/test-driver builds pass, including exact sandbox and shipping-probe exclusion.
- All **41 direct non-hosted AppKit unit cases pass on arm64**, and all **41 pass under installed Rosetta on x86_64**, with no skips and the unchanged 30-second per-case/180-second command bounds. Both runs use the same universal test bundle and sanitized environment. This does not replace required Xcode UI CI or physical Intel testing.
- The actual isolated app passes the complete original cold-launch/file/dirty-recovery/restart/independent caret-and-viewport regression on Apple silicon. A separate host also requests and verifies **x86_64 for every returned app process** and passes those same assertions under Rosetta, including explicit Intel isolation-guard launches. Original ten-second observation limits remain intact. The private hosts preserve fixtures; one incorrect object-count preparation assertion stopped before compilation/launch, was recorded, and was corrected to verify all ten actual source objects.
- The original two-case idle collector passes all **122 active samples**, normal Quit, exact recovery and unchanged source/binary/sandbox checks on this combined implementation. Maximum empty/20-tab RSS is **91.891/99.984 MiB**. Empty RSS still exceeds 80 MiB by **11.891 MiB**; the 20-tab result is below 150 MiB on this Mac. This is one independent window per case, not a controlled attribution of each difference to a specific PR. Raw CPU and physical-footprint observations are retained separately; the unchanged 80/150 MiB targets and minimum hardware acceptance remain explicit.
- A new local automatic archive and Store package export pass strict verification for both architectures, Apple chain/team and pinned distribution/installer certificates, embedded Store profile, Hardened Runtime, exact four product permissions, privacy/icon/version resources, no quarantine and no test/performance code. Package SHA-256: `5102f181b28447192836529659cfcda5022ae58d5e52ff34db5e3051cefc88c6`. The earlier signed package remains retained separately.

The signed package was not installed or uploaded; no tag, GitHub release or App Review submission was created. Full UI CI and individual PR review/merges remain open. The separate #45 private dispatch observations do not certify physical event-to-visible latency or replace the complete original before/after interaction and launch protocols. Physical Intel/M1, macOS 14 runtime, VoiceOver/real IMEs, publisher-specific listing decisions, public support/policy URLs and authenticated App Store Connect/TestFlight gates remain unverified.

The runner is online and idle with its `notehush` routing label held. Apple's read-only Automation Mode check reports disabled/requires owner authentication; no authorization policy was changed. Native UI CI resumes only after that prerequisite and within the confirmed exclusive-input window.

## Earlier nine-PR evidence, preserved

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

## Static minimum-OS linkage inspection

A read-only inspection on 2026-09-09 at 04:05 UTC used the exact previously verified Store-exported executable (`29c563b7e046b8d7beed589b9de276797924a7da76418b6ab26639cf55c4d87b`, source `9557aec`). Both arm64 and x86_64 load commands declare macOS 14.0, and both mark `CFAttributedStringGetStatisticalWritingDirections` as a weak external import. The source gates this macOS 26 optimization with its availability check. Raw `nm`/`otool` output hashes and the private artifact location are included in the existing numeric evidence index. The binary remained unchanged; no compiler or app was launched.

This checks deployment metadata and that specific optional API's linkage. It does not establish actual macOS 14 execution, physical Intel compatibility, VoiceOver/IME behavior, or the older system's performance. Those #13 gates remain unverified.
