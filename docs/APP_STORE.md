# Mac App Store readiness

Reviewed 2026-09-08; file-metadata reasons rechecked 2026-09-07 for #31. This matrix covers requirements relevant to NoteHush's planned offline plain-text editor. Apple's policies change and App Review is discretionary; neither this file nor a successful archive guarantees approval. All rows begin as pending until evidence is attached. The [submission packet](store/SUBMISSION.md) records current preparation and remaining gates.

| Area / guidance | Implementation or evidence required | Gate |
| --- | --- | --- |
| 2.1 completeness | All advertised functions work, no placeholder UI, tested production backend-free app; reviewer instructions | M5/M6 |
| 2.3 accurate metadata | Actual screenshots, correct description, age-rating questionnaire, category, supported systems and limitations | M6 |
| 2.4.5 macOS | Sandbox; all resources in app bundle; supported installation/update behavior; no auto-launch, privilege escalation, external licensing or non-Store updater | M1/M6 |
| 2.5 software requirements | Public APIs; stable SDK; no downloaded/executed code; no hidden behavior | M1/M5 |
| 4.1 intellectual property | Original NoteHush icon/name/UI; no Microsoft assets or implication of affiliation; confirm rights/title availability | M6 |
| 4.2 minimum functionality | Useful native editor with tabs, robust recovery, search and file operations; demonstrated in review notes | M5/M6 |
| 5.1 privacy | Public policy URL and accessible in-app policy; App Privacy answers; required-reason API audit, bundled manifest, no tracking | M1/M6 |
| Payments / accounts | No account or IAP in v1. If paid download, configure price and agreements in App Store Connect; revisit rules before monetization changes | M6 |
| Security | Least-privilege entitlements, no network capability, no secrets in source/CI logs, secure bookmark handling | M1/M3/M6 |
| Human interface / accessibility | Native menus/shortcuts, keyboard/VoiceOver, contrast, reduced motion, text input; truthful accessibility declarations | M5 |
| Identity/signing | Confirm team and bundle ID, unique app record/SKU, distribution signing/profiles, hardened runtime, correct entitlements | M6 |
| Delivery | Current accepted Xcode/SDK, valid archive/export, no quarantine xattr in delivered app, validated upload | M6 |
| Operational/legal | Publisher contact, support URL, territorial trader status when applicable, export-compliance responses, age-rating questions, current agreements | M6 |

## Concrete v1 entitlement budget

- `com.apple.security.app-sandbox = true` from first build.
- `com.apple.security.files.user-selected.read-write = true` for native panels.
- `com.apple.security.files.bookmarks.app-scope = true` for persistent file access (implemented in #7).
- `com.apple.security.print = true` for user-initiated native printing and PDF output (implemented in #9).
- No network client/server, microphone, camera, contacts, location, automation, app groups, iCloud or broad filesystem exception.

Privacy manifest: `NSPrivacyTracking = false`, no tracking domains, no collected data types. Issue #6 uses `fstat` for identity/type/size of user-selected files and declares `NSPrivacyAccessedAPICategoryFileTimestamp` with reason `3B52.1`. Issue #31 adds `fstat`/`lstat` fingerprints for private recovery blobs, declaring reason `C617.1` for app-container metadata. These uses match [Apple's approved file-metadata reasons](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitypereasons), rechecked 2026-09-07. No metadata leaves the device. Configuration validation requires both reasons, and archive validation checks the bundled manifest matches source. UserDefaults for app-owned preferences generally uses reason CA92.1; add it only when implemented and verify the approved reason against actual usage. Inspect the privacy report of the final archive.

## Store material checklist

Implementation sub-issue #53 of release gate #15 prepares an original icon asset catalog, [English metadata](store/metadata.en-US.json), and [static support/privacy pages](../website/README.md). Integrate these sources through #53's passing, reviewed PR; keep #15 open for public deployment, publisher approval, in-app URL integration and final app screenshots. Archive validation now requires the compiled icon and `ITSAppUsesNonExemptEncryption = false`, matching the documented SHA-only application audit; this is not a submitted export declaration.

- Title NoteHush and subtitle; App Store Connect verifies title reservation.
- Original 1024 px source icon and required macOS asset sizes, no Microsoft imagery.
- Screenshots from final native UI at Apple's current accepted sizes; no fabricated UI.
- English description, keywords, release notes and copyright/legal entity.
- Public HTTPS support and privacy pages. The private GitHub repository cannot serve as the public support/privacy destination.
- Privacy answers: no developer collection only if verified in final build. Explain local session data separately.
- Completed age-rating, encryption/export, content-rights, accessibility, pricing and availability fields.
- Review notes: no login; how to create tabs, quit and restore drafts; explicit save behavior and local-only data.
- Public release only after successful store review or an explicitly chosen launch timing.

## Publisher input required before submission

Confirm registered seller/team, bundle identifier, contact/support destination, pricing, territories and trader declarations. Configure signing and App Store Connect credentials through a keychain or GitHub environment secrets, never paste private keys into issues or chat. These are distribution gates; development and unsigned CI can proceed now.

## Primary references

- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [Submitting apps](https://developer.apple.com/app-store/submitting/)
- [Upcoming requirements](https://developer.apple.com/news/upcoming-requirements/)
- [App Sandbox](https://developer.apple.com/documentation/security/app-sandbox)
- [Privacy manifests](https://developer.apple.com/documentation/bundleresources/privacy_manifest_files)
- [Required reason API categories](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype)
- [Approved required-reason API uses](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitypereasons)

Check current requirements again before uploading; do not assume that mobile platform SDK minimums imply the same macOS deployment target. Initial local tooling: Xcode 26.6, with macOS 14 deployment target selected as a product support choice.
