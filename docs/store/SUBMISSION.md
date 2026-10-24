# Store submission packet

Status: sources prepared under implementation sub-issue #53 of release gate #15, not submitted. Use [the English metadata](metadata.en-US.json) only after its advertised functionality and supported systems pass final acceptance. Publisher fields, screenshots, accessibility claims and the final questionnaire responses remain unset rather than guessed.

## Review notes draft

NoteHush is a native AppKit plain-text editor for macOS, with no account, login, in-app purchase, remote content service or developer analytics SDK. No credentials are required to review it.

To check its main behavior:

1. Create two tabs with Command+N and enter invented text in both. Switch tabs with Control+Tab or by clicking the tab titles.
2. Select part of the text, scroll if needed, and quit with Command+Q. There is intentionally no unsaved-file confirmation. Open NoteHush again: the tabs, selected tab, text and editing position should return.
3. Use Save or Save As to write a selected draft through the standard macOS panel. Private recovery is separate from explicit saving and does not silently overwrite the file.
4. Close a tab with Command+W and restore it with Shift+Command+T. The app retains up to 20 recently closed tabs; File → Clear Recently Closed Tabs clears that list.
5. Try Find/Replace, Go to Line, Settings, Print and Print Selection through the native menus. Printing uses macOS services and may require a configured destination.

The red workspace close control quits with the same recovery behavior as Command+Q. This is a deliberate product feature. Closing Settings does not quit the app. Undo stacks are per open tab within the current session; persisted recovery restores text and presentation state, not undo history.

Files over 100 MiB and unsupported/invalid encodings are rejected without modifying the original. The app does not render rich-text or Office documents. The app has no network entitlement; public support/privacy links must be connected through the user's browser before submission. Add the final public URLs and publisher review contact here after confirming them.

## Questionnaire preparation

| Field | Proposed technical answer | Final action |
| --- | --- | --- |
| App Privacy | No data collected by the app; no tracking, ads or analytics SDK | Recheck the signed candidate and publisher support practices before submitting |
| Account / login / IAP | None | Verify installed build and final metadata |
| User-generated content | Local text editing only; no public sharing/feed or content service | Answer the actual questionnaire's definitions, not merely whether users can type |
| Messaging / chat / unrestricted web browsing / AI generation | No such app features | Confirm against the final binary and current questions |
| Predefined mature, violent, sexual, gambling, medical or drug-related content | None supplied by NoteHush | Complete Apple's current questionnaire; do not assign an age rating manually here |
| Accessibility declarations | Unset | Claim only capabilities that pass the specific Apple evaluation criteria in #13 |
| Content rights | Original app and icon; no licensed media catalogue | Publisher confirms name/branding rights and answers the content-rights question |
| Export compliance | No non-exempt encryption identified in the app | Publisher completes the submission questions and any territorial obligations |
| Copyright / seller / support contact | Unset | Confirm the registered publisher; do not infer it from the GitHub organization |
| Price / territories / trader status | Unset | Publisher decision and legal declarations required |

Encryption audit on 2026-09-08: application/core sources import CryptoKit only to calculate SHA-256 file/recovery integrity hashes. There is no custom encryption implementation, network client, encryption UI or third-party runtime cryptography. The app's `ITSAppUsesNonExemptEncryption` is therefore `false`; this technical configuration does not submit a legal declaration on the publisher's behalf. Apple describes [OS-provided cryptography](https://developer.apple.com/help/app-store-connect/reference/app-information/export-compliance-documentation-for-encryption) and [the submission questions](https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance). Re-audit this flag if app functionality/dependencies change.

The metadata validator must count the keyword field in UTF-8 bytes (100 maximum), not characters. Keep name/subtitle within 30 characters, promotional text within 170 characters and description within 4,000 characters. The current [platform field reference](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information/) describes the localized metadata fields. Do not add competitor names or unsupported performance claims.

## Screenshots

Capture the final installed candidate using only generated sample text. Do not reuse old validation images as evidence of the release build, reconstruct the app UI or capture private documents/system dialogs. Before capture, verify the current accepted [macOS screenshot sizes](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/), the exact source/build and the supported display appearance.

Suggested set: workspace with several tabs and one unsaved draft; Find/Replace in a generated document; font/wrap settings with the editor visible; local draft restoration after a normal restart. Each image must show real behavior in the final UI, with no unmeasured speed claims. Keep originals and any approved framing separately, record dimensions and build provenance, and populate `screenshotAssets` only after review.

## Public pages and in-app access

[Website sources](../../website/) contain the home, support and privacy pages. [The website guide](../../website/README.md) describes local preview and publisher configuration. The private repository URL is not a public policy/support destination. Final work still includes public HTTPS deployment, anonymous access checks and wiring the confirmed URLs into accessible in-app Help commands. Do not substitute a broken or hypothetical domain.

The privacy copy must be reviewed by the publisher, especially the support-message retention/deletion practice and hosting provider. The draft distinguishes local app storage from explicit saves, system backups, printing, Apple services, website hosting and voluntary support contact. No data collection, storage provider or company identity should be invented to fill the Store forms.

Implementation sub-issue #68 adds Help → Privacy… with a native offline explanation of current local app behavior. It is not the completed publisher-specific public policy. Keep its text consistent with that policy and add the verified public privacy/support links before marking this gate complete. Apple's in-app and metadata privacy-policy access requirement was rechecked against [guideline 5.1.1(i)](https://developer.apple.com/app-store/review/guidelines/#data-collection-and-storage) on 2026-09-09 (local time).

## Current readiness matrix

The current Apple-source recheck and gate-by-gate evidence are in [APPLE_REVIEW_READINESS.md](APPLE_REVIEW_READINESS.md). The previous matrix is superseded; publisher, public-policy, final screenshot, signed TestFlight and App Review gates remain open. Version 1 and its GitHub release remain gated by #16.
