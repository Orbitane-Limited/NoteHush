# Store materials preparation — 2026-09-08

Implementation sub-issue: #53; parent release gate: #15. Implementation commit: `c61d31c529a5ef49d504cb8a80d01ac345a00a07`, branch `issue-53/store-materials`, based on main `2c786fac01a59e548475c20f985050c0a430e992`. This branch was renamed from `issue-15/store-materials` when source integration and final Store readiness were separated. Its code and recorded validation are unchanged. Local date is 2026-09-08 in Asia/Karachi; execution occurred on 2026-09-07 UTC.

## Prepared candidate

- Original geometric tabbed-note icon, vector master and all ten macOS AppIcon PNG slots. Xcode compiles the catalog into `AppIcon.icns` and records the matching bundle icon fields.
- `ITSAppUsesNonExemptEncryption = false`, based on the application/core source audit finding only Apple CryptoKit SHA-256 integrity hashes. This does not submit the publisher's export declaration.
- English Store copy, review steps and a questionnaire/readiness packet. Unconfirmed publisher/legal fields, accessibility declarations and actual app screenshots remain unset.
- Static home, support and privacy pages with light/dark styling, responsive layout, local artwork and no scripts/third-party web resources. Public generation rejects missing publisher details, placeholder/unsafe destinations and overwriting an existing output/report. Local previews are visibly marked unpublished and non-indexable.

The app's editing/recovery behavior and version `0.1.0 (1)` are unchanged. No native NoteHush GUI tests or app launches ran during this preparation, and no site, Store metadata, signing asset or release was published.

## Executed validation

| Check | Result | Evidence / scope |
| --- | --- | --- |
| Icon renderer | Passed Swift 6 strict concurrency and formatting | Offscreen Core Graphics; no keyboard/mouse use or app data |
| All icon slots | Passed | Ten distinct size/scale slots, PNG dimensions checked; 1024-pixel largest source |
| Debug build | Passed | `build/logs/store-materials-final-debug-build.log` |
| Universal unsigned Release archive | Passed | `build/logs/store-materials-final-release-build.log`; arm64 and x86_64 verified |
| Bundled icon / export metadata / privacy / version | Passed | Final archive configuration validator, icon decoded from `.icns` and visually inspected |
| Repository automation | 32 tests passed | Includes website configuration rejection, HTML escaping, explicit preview state and existing-output preservation |
| Swift formatting / docs links / whitespace | Passed | App/core/tests/package plus renderer; configuration validator and `git diff --check` |
| Store text limits | Passed | Name 8/30, subtitle 27/30, promotion 162/170, description 1,403/4,000 characters; keywords 85/100 UTF-8 bytes |
| Website browser checks | Nine combinations passed | All three pages at 1,280 px dark, 390 px light and 320 px light; actual viewport width, no horizontal overflow, loaded images and keyboard access to skip link |
| Browser/server cleanup | Passed for final protocol | Playwright browser/context and loopback fixture server closed cleanly |

Final unsigned executable SHA-256: `3a2a6e87c05750f9d8530beb3ec2b8223f16aa518e492bb15f40a1242ba0d06c`. It belongs to `build/NoteHush-materials-final.xcarchive`; it is not an App Store signed binary. Source/resources were committed unchanged after these builds. `build/logs/store-materials-final-archive.json` records the observed version, icon fields, encryption flag and executable hash.

Website measurements are in [the layout report](2026-09-08-website-layouts.json). [Home](images/2026-09-08-site-home.png), [mobile support](images/2026-09-08-site-support-mobile.png) and [privacy](images/2026-09-08-site-privacy.png) are **local website previews**, not screenshots of NoteHush or App Store submission images. The publisher placeholders are deliberately visible. The rendered pages were visually inspected in addition to the overflow/image checks. No VoiceOver, public-host availability or complete accessibility certification is claimed.

## Browser setup failures retained

Two initial Chrome CLI capture attempts produced images but did not exit within their declared limits (45 seconds for desktop, 30 seconds for the later support attempt). The narrow CLI capture was clipped and did not establish a correct mobile viewport. Owned browser process groups were terminated and their temporary profiles/loopback servers cleaned up. The unsuccessful protocols and output remain under `build/site-visual-checks/`, `build/site-visual-checks-remaining/` and the corresponding untracked driver scripts. Their results were not counted as passing browser checks.

The final protocol uses explicit Playwright viewport sizes and checks the browser's reported dimensions, then closes the browser through its API. All nine cases and process cleanup passed. Playwright 1.62.0 was installed only into ignored `build/site-qa-venv`; it uses the installed Chrome in an isolated headless session with browser sandboxing enabled. Its downloaded distribution matched the official PyPI digest. It is authoring/validation tooling, not a NoteHush dependency. The local install report, exact script, six full-page images and successful output are retained in `build/logs/site-qa-install.json`, `build/check_site_playwright.py`, `build/site-playwright-checks/` and `build/logs/site-playwright-checks.log`.

## Remaining release gates

- Confirm publisher identity, public support address, hosting and the privacy policy's operational promises. Build and deploy the actual public pages, then verify anonymous HTTPS access.
- Connect the verified policy/support URLs to accessible in-app Help commands and Store metadata. No hypothetical URL was added to the app.
- Confirm price, territories, content rights and applicable trader/legal declarations; complete the actual Apple forms.
- Capture the final installed app using generated fixtures; no Store screenshot assets were fabricated or marked complete.
- Check the compiled app icon in Dock/Finder/About, supported OS/architecture combinations, appearance variants and accessibility settings.
- Resolve the outstanding M5 functional/performance issues and complete #13 accessibility/IME/hardware acceptance, #14 signing/TestFlight and #16 release gates.

No issue was closed, no branch was merged, and no PR was opened: this repository's PR event immediately runs the native self-hosted suite, whose next exclusive-input window remains pending. The branch and these concrete materials can be reviewed before that run.
