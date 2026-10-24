# Versioning and release process

Use semantic versioning for product versions. Begin at `0.1.0`; reserve `1.0.0` for the completed v1 acceptance criteria. `Config/Version.xcconfig` is the source of truth once the foundation lands. `MARKETING_VERSION` is three numeric components; prerelease labels belong in Git tags/release titles, not CFBundleShortVersionString. Every App Store/TestFlight upload uses a new, monotonically increasing `CURRENT_PROJECT_VERSION` integer.

## Integration

Issue branch -> pull request -> required CI and review -> squash merge to main. Keep main buildable. Update CHANGELOG under Unreleased. Do not tag a partially implemented build as production-ready.

## Delivery stages

1. **PR CI:** formatting, doc/config checks, core tests, unsigned macOS app build, optimized universal archive, retained logs. No signing secrets on pull requests.
2. **Internal artifacts:** main-branch CI archives are unsigned engineering artifacts, not installable App Store builds. Labels and filenames must say unsigned.
3. **Signed candidate:** workflow_dispatch from a reviewed release commit/tag, protected `app-store` environment, App Store Connect API key and signing assets, temporary keychain/profile installation with unconditional cleanup, archive/export validation, TestFlight upload. Implemented in M6 after identity is configured.
4. **Store submission:** TestFlight/manual acceptance, metadata and privacy checks, publisher details confirmed, then submit for App Review. Store release can be manual after approval.
5. **GitHub release:** from the exact approved release commit. Tag `v1.0.0`; create draft first, attach changelog, tested matrix and checksums for approved artifacts, then publish when all gates pass. Do not attach an unsigned app disguised as a production installer. For Mac App Store-only distribution, link to the listing; a separate notarized Developer ID download is a separate future channel.

## Release checklist

- [ ] All milestone issues required for v1 closed; no release-blocking defect.
- [ ] Version/build updated in issue branch, validated against tag/archive and prior upload.
- [ ] CI green at exact release commit; tested source matches signed binary.
- [ ] TESTING manual, recovery, migration, performance, accessibility and compatibility evidence attached.
- [ ] APP_STORE matrix complete; accepted toolchain rechecked.
- [ ] Distribution identity, entitlement and privacy report inspected; archive validates.
- [ ] TestFlight installation/upgrade passes; public support/privacy URLs work.
- [ ] Store metadata and legal fields confirmed; review notes prepared.
- [ ] Store approval/release timing recorded; GitHub release draft finalized.

Rollback: halt phased release where available; ship a higher build/version containing a compatible fix. Never downgrade recovery schema destructively. Keep previous recovery generations and tag every released source. Do not replace a published tag with different code.

## CI security

Use least-privilege permissions, pinned action commit SHAs and Dependabot updates. Never run untrusted PR code with signing secrets or `pull_request_target`. Avoid printing credentials. Protect the signing environment and release tags when the repository plan permits. Branch protection availability can depend on the GitHub plan for private repositories; record any unmet enforcement instead of claiming it is enabled.

## Guarded App Store delivery setup

`.github/workflows/app-store-delivery.yml` is a main-only manual workflow. It requires the
`confirm_upload` input to be true, then runs the complete `scripts/check.sh` suite at the selected
main commit before creating a signed Mac App Store package. It uploads the package with Apple's
`altool`, retains only the package, checksum, and non-secret delivery manifest on success, and
keeps diagnostics for failed/cancelled runs. A successful upload means Apple received the build;
processing and TestFlight installation are separate release gates.

Before the first run, the publisher must create the explicit `pk.codehub.NoteHush` app record in
App Store Connect and configure the GitHub environment:

1. Open repository **Settings → Environments → New environment** and name it `app-store`.
2. Restrict deployments to the `main` branch and set a required reviewer. Keep environment secrets
   out of repository-level secrets and never use them in pull request workflows.
3. Add these exact environment secrets:

   | Secret | Value |
   | --- | --- |
   | `ASC_KEY_ID` | Key ID for a dedicated App Store Connect team API key |
   | `ASC_ISSUER_ID` | Team API key issuer ID |
   | `ASC_PRIVATE_KEY_BASE64` | Base64 of the downloaded Team API `.p8` private key; use the minimum Developer role needed to upload builds |
   | `MAC_APP_DISTRIBUTION_P12_BASE64` | Base64 of the Apple Distribution certificate `.p12` |
   | `MAC_APP_DISTRIBUTION_P12_PASSWORD` | Password used when exporting that `.p12` |
   | `MAC_INSTALLER_DISTRIBUTION_P12_BASE64` | Base64 of the Mac Installer Distribution certificate `.p12` |
   | `MAC_INSTALLER_DISTRIBUTION_P12_PASSWORD` | Password used when exporting that `.p12` |
   | `MAC_APP_STORE_PROFILE_BASE64` | Base64 of the `NoteHush Mac App Store Distribution` `.provisionprofile` |

   Create base64 values locally with `base64 < file | tr -d '\n'`, then paste each value directly
   into the corresponding GitHub environment secret field. Never place the output in source files,
   workflow logs, issues, pull requests, or chat. Certificate renewal requires replacing the
   relevant certificate/profile secrets together and rerunning signing validation.

4. Dispatch **Actions → App Store delivery → Run workflow** from `main`. The job is skipped unless
   `confirm_upload` is true. Choose true only when ready to send that signed build to Apple. The
   protected environment reviewer must approve the job before its secrets become available.
5. Wait for App Store Connect processing, then install the candidate with TestFlight and complete
   the lifecycle, file-access, accessibility, and printing acceptance before closing #14.

The workflow stores certificates, the archive, and the API key in a mode-restricted per-run
directory. It installs the provisioning profile at macOS's standard per-user profile location so
Xcode can use it; cleanup removes it only when its UUID and SHA-256 still match the ownership
manifest. The temporary keychain is added to the user's search list only for signing, then cleanup
restores the prior list. The API key exists only in the upload step's isolated temporary `HOME`.

The workflow uses GitHub-hosted macOS runners, whose machines are discarded after the job. If
cleanup fails while the runner is still available, inspect that run's `$RUNNER_TEMP` manifest and
logs before any manual cleanup. Do not copy signing material from the runner into an artifact. On a
persistent runner, run the cleanup command only in the same account and after verifying the
manifest; it refuses malformed or foreign ownership records.
