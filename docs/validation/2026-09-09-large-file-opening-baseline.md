# Native 10 MiB file-opening baseline, 2026-09-09

The [original protocol](../LARGE_FILE_OPENING.md) passes all 40 fresh-process observations and full post-Quit recovery/source verification on clean implementation `1a1154d96f542f6c2a17294590b414f992fe34a6`, based on main `bb49b49`. No shipping app behavior changed. Version remains **0.1.0 (1)**.

| Generated 10 MiB file | Observations | Median request-to-checkpoint | p95 request-to-checkpoint | Maximum |
| --- | ---: | ---: | ---: | ---: |
| ASCII CRLF | 20 | 280.299 ms | 414.136 ms | 485.963 ms |
| Arabic/combining-mark/emoji CRLF | 20 | 9,585.451 ms | 9,654.208 ms | 9,939.953 ms |

These intervals include LaunchServices, app processing, recovery scheduling/I/O and independent host decoding. They do not measure a physical frame or establish that the window stayed interactive. The mixed-script maximum is close to the unchanged ten-second observation bound. A passing correctness run does not close the PRD performance gate or authorize a threshold increase.

All UTF-8 bytes, tab IDs/order, active tab, UTF-16 selection, viewport, preferences/window frame, encoding/file binding/source identity and normal Quit were verified. Every original file remained unchanged. There were no retries, skipped cases, filtered outliers or cleanup of failed/successful fixtures. The summarizer accepted all 162 expected journal records and required successful collector exit, unchanged clean source, app/harness hashes and exact product sandbox permissions before/after. The retained [numeric report](2026-09-09-large-file-opening-baseline.json) contains every timing sample, environment, hashes and private artifact references, without fixture paths/bookmarks/text.

Host: M4 Pro, 24 GiB, arm64, macOS 26.6.2 (25G83), Xcode 26.6 (17F113), Swift 6.3.3, AC power, low-power mode off and nominal initial thermal state. Warm filesystem caches; fresh processes. The user reserved exclusive awake Mac use; the self-hosted runner was online/idle with routing held and no other native jobs ran. This does not prove physical M1/8 GiB or macOS 14 acceptance. Collection/build envelope: 01:51:20–01:55:26 UTC.

Validation: 57 repository checks, 88 Swift tests, strict formatting/configuration, optimized app and Release host builds pass. A later validation-only integration attempt exposed a Python test-discovery basename collision before tests or measurements ran. Commit `d2a2bfb` renames that test and restores the temporary import path; all 57 issue-branch repository checks pass again. The app/harness and this baseline are unchanged. The original failure log is retained. Full native UI CI and review remain required; no release, tag, package installation or upload was performed.

The candidate paragraph-layout implementation can now be compared under this same complete protocol on the separate validation branch. Keep the original launch/interaction protocols, physical-frame and interactive-window targets, 100 MiB/pathological paragraphs, minimum hardware/OS and App Store gates open.
