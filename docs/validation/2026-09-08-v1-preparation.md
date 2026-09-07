# Combined v1 preparation checks — 2026-09-08

Branch: `validation/v1-preparation`. Final built source: `03def2051f25a71566038fb5684bbad60ddc8d6b`, based on main `2c786fac01a59e548475c20f985050c0a430e992` through the prior M5 validation branch. Local date is 2026-09-08 in Asia/Karachi; execution occurred on 2026-09-07 UTC. Engineering version remains `0.1.0 (1)`.

This checkout combines prepared issue changes to check their compatibility. Individual issue PRs, complete CI and resolved review remain required for integration into main. No native NoteHush app or GUI test was launched during these checks; no signing credential, account, public website or release was published.

## Included sources

| Candidate | Source included |
| --- | --- |
| #43, #46, #48, #50 | Existing M5 integration head `f18976483642dd8da8dae1bc28d1636e00ce7aae`, measured code `d4910767fae7e4d8e06ebd2c65170f930780a11d` |
| #29 isolated Undo diagnostics | `d45b7b64512d3218aece6a067ca4c513d722081f` |
| #52 Store delivery implementation, parent #14 | `1f5cbee1f255a0391a25a5db2c4a712dea4ddb76` |
| #53 original icon and Store source materials, parent #15 | `dd27a087e30cad673fd471bff8a5db4da9a5ff72` |
| #54 custom tab insertion indicator, parent #13 | `eb0799d5437c28b92219d8950315fc3cce3b7ae2` |

Project-file conflicts were resolved by retaining both performance and Undo diagnostic source entries and the icon resource entries. The archive validator retains the complete performance-marker checks, Undo exclusion checks across the executable and adjacent libraries, and the icon/export metadata checks. Documentation conflicts retain each candidate's requirements and evidence. No functional assertions, timeouts or release gates were removed.

## Executed checks

The initial combined source `fbefd0650b8b805b74969585dfe9329c399e729d` passed:

- 71 repository automation tests, covering the combined existing and newly prepared suites.
- 85 Foundation core tests with code coverage enabled.
- 83 Debug plus 83 Release SIGKILL recovery drills; all expected publication phases ran and exact workspace/source-byte checks passed.
- Configuration and relative-document links, Xcode project syntax, strict Swift formatting and actionlint 1.7.12 for the Store workflow. Optional ShellCheck and pyflakes integrations were not available and were not claimed.
- Debug build, universal unsigned Release archive, and isolated optimized build-for-testing with exact product entitlements. These commands compile but do not execute native app tests.

That build exposed the existing deprecated `TabBarView` custom-box border setting. Issue #54's independently built one-line fix was then included. The only app-source difference between the initial combined source and final source `03def2051f25a71566038fb5684bbad60ddc8d6b` is `insertion.borderWidth = 0` in place of the old border setting; other differences are documentation. Core, recovery and repository-test sources are unchanged.

Final source `03def2051f25a71566038fb5684bbad60ddc8d6b` passed fresh configuration/format checks and all three builds again: Debug, universal unsigned Release archive and isolated optimized build-for-testing. The app-source deprecation warning is absent from all three final build logs. The compiler's App Intents metadata warning remains because the app does not link AppIntents. The earlier successful test results are tied to their original source above; no new native runtime or performance result is inferred from these builds.

The final unsigned archive is `build/NoteHush-prepared.xcarchive`. Its executable has both `arm64` and `x86_64`; its SHA-256 is `55a222e67f2ec44fe4146015686df17eed9c15703c09ea81d3a0968dfcd56266`. The original icon, encryption flag, bundle/version/minimum OS, privacy manifest and release isolation checks passed. The [product manifest](2026-09-08-prepared-products.json) records every executable/library hash and actual architecture, including Xcode's separate Debug code library. Undo diagnostics are absent from all three built products.

Storage guards passed before each build stage. The initial observation recorded approximately 113 GB available against a 49.4 GB requirement on the workspace/temporary volume. The guard removes no files. The self-hosted runner was observed online and idle before compilation, with no in-progress Actions run. This is a local preparation check, not a GitHub CI success.

## Retained local evidence

- `build/check_combined_headless.sh`: exact initial headless commands; outputs in `build/logs/combined-*`, `release-archive.log`, and the retained `initial-combined-performance-*` files.
- `build/check_final_prepared_builds.sh`: final build commands; outputs in `build/logs/final-prepared-*` and the final `performance-build*` files. The initial archive remains at `build/NoteHush-unsigned.xcarchive`.
- `build/logs/combined-products.json` and `final-prepared-products.json`: actual product identities, all code hashes and explicit unsigned/no-GUI flags.
- Individual [Undo](2026-09-07-undo-diagnostic.md), [delivery](2026-09-08-store-delivery-preparation.md), [Store materials](2026-09-08-store-materials-preparation.md) and [indicator](2026-09-08-tab-indicator.md) records retain their separate source revisions, executed checks and limitations.

## Remaining v1 gates

- **Native correctness:** the [prior M5 CI failure](2026-09-07-m5-integration.md) and issue #29 remain unresolved. Execute the prepared isolated Undo diagnostic protocol in a confirmed awake/unlocked exclusive-input window, resolve the observed cause, then complete native/full CI and individual PR review. The focused diagnostic plan belongs to issue #29's recorded binary, not this newer combined product.
- **Performance:** mixed-script typing/tab-switch budgets and minimum M1/8 GB measurements remain open under #12/#45. This build does not reuse timings from a different source as new performance evidence.
- **Accessibility/compatibility:** actual VoiceOver, full keyboard, contrast/motion, IME/RTL, supported OS/Intel runtime, monitor and installation checks remain open under #13. The #54 native insertion-indicator check is also pending.
- **Distribution:** confirm publisher/team and app identity; supply correct Store application/installer identities and profile; resolve the actual GitHub signing-environment constraint; validate a real signed upload, Apple processing and installed TestFlight behavior, including physical printing. The private organization was observed on GitHub Free; its required protected environment is unavailable under the current plan. See [delivery setup](../APP_STORE_DELIVERY.md). No plan/visibility change has been made.
- **Public materials:** confirm support contact, publisher policy operations, domain/hosting, final Store fields and price/territories; deploy and verify anonymous HTTPS pages, integrate their real in-app URLs, and capture the final installed app. The local website previews are not Store screenshots.
- **Release:** main integration, full acceptance, final version/build, App Review and GitHub release remain gated by #16. No release issue was closed based on this preparation.
