# Automatic Store signing and profile verification

Date: 2026-09-08 UTC. Issue #52 / PR #61; parent release gate #14.

## Actual artifacts

The clean main source `bb49b49c5cb3ead161f774d087d9fd26481f73e1` passed complete self-hosted [CI 34210857082](https://github.com/Orbitane-Limited/NoteHush/actions/runs/34210857082), including all 62 native cases and both artifact uploads. The source remains engineering version **0.1.0 (1)**. No remaining issue is certified by that earlier main run.

Using the configured Xcode account, an explicit team `4T674XS5MF`, `Apple Development` identity and `-allowProvisioningUpdates`, a fresh Release archive completed at 10:05:51 UTC in 32.840 seconds. It is universal and has a valid Apple Development signature and exactly the four product permissions. Its development certificate fingerprint is `B74989FCD40F6683A6234B2989D412453714FEC7`. This development archive contains no profile and is not itself a distribution candidate.

A separate local export completed at 10:08:39 UTC in 24.377 seconds. Its options specify `app-store-connect`, destination `export`, automatic signing, the confirmed team, both existing Store certificate fingerprints and disabled version/build management. Xcode supplied the explicit Mac Store provisioning profile. No private key was exported, device registration requested, app launched, package installed or upload performed.

| Exported artifact check | Result |
| --- | --- |
| Package signature and exact installer certificate | Passed |
| arm64 and x86_64 application signatures / Hardened Runtime | Passed |
| Existing Apple Distribution certificate pin | Passed on both architectures |
| Embedded profile team, explicit app ID, expiry and authorized certificate | Passed |
| Four product permissions plus matching application/team identity | Passed; no added file/network/debug permission |
| Version/build, macOS target, original icon, privacy and export metadata | Passed |
| Release/test-probe exclusion and absence of quarantine | Passed |
| Strict local Store verifier | Passed after the UUID correction below |
| Apple server validation/processing, TestFlight install, App Review | Not performed |

Package SHA-256: `51f55e7c46fd06949705a591f5dc924a7ab50b996beaab06a536cccd40e2cdd6`.
Exported executable SHA-256: `cb058a460c68b48a84adb4c29ba12ed8dbe79c3c134fd315d6a61569211af2a1`.
The package and exported signatures omit trusted timestamps, as permitted for Store distribution; they are not Developer ID/notarization artifacts.

## Confirmed verifier defect and regression

The first strict inspection rejected Xcode's valid lowercase profile UUID. The checker required uppercase spelling, and the temporary-profile installer repeated that assumption. Its filename regex also accepted 36 hyphens. UUID hexadecimal letters may use upper, lower or mixed case ([RFC 9562, section 4](https://www.rfc-editor.org/rfc/rfc9562.html#section-4)).

A shared parser now requires the complete canonical hex-and-dash structure while accepting either letter case. Profile metadata is preserved; only the owned installation filename is normalized to uppercase so existing cleanup records and ownership checks remain consistent. No profile, identity, certificate, permission or expiration check is removed.

Generated regressions reproduced rejected lowercase/mixed profiles and failed lowercase installation before the correction. Malformed-identifier cases also reproduced unsafe ownership publication for the all-hyphen string and inconsistent type errors. After the correction, all **78 repository tests** pass, including these cases, exact permissions, preserved preexisting profiles, changed-file protection, native signature requirements, quarantine and failure cleanup. Configuration/link, whitespace and actionlint checks pass. The original failed inspection and before/after test logs remain retained.

The unchanged exported package then passed the complete native verifier. That verification used the explicitly recorded parser-source SHA-256 `82941decbc2550f51792e12b8b4b94fccade665153b22718eddf778a06b6d89e`; it does not assert that the unmerged PR already passed final GitHub CI. Native CI remains queued after the confirmed exclusive Mac window.

## Remaining boundaries

The owner no longer needs to create or download this profile manually. Apple documents [automatic distribution profile management](https://developer.apple.com/help/account/provisioning-profiles/create-an-app-store-provisioning-profile/) and confirms that [TestFlight requires a provisioning profile](https://developer.apple.com/documentation/technotes/tn3125-inside-code-signing-provisioning-profiles). Local inspection is not Apple server acceptance.

Final product fixes, performance and compatibility/accessibility gates, public support/policy details, the matching Store app record, reviewed-source candidate, upload processing and installed TestFlight acceptance remain required. There is no v1 tag or GitHub release. Earlier profile-less engineering artifacts stay separate and are not relabeled as valid candidates.

Private logs, profile, development/public certificate evidence, complete signing reports and the package remain under root `build/store-signing-verification/automatic-archive-6BF322B2-80FC-44F2-BA06-5DE5B6FC2C66/`. Raw account/provisioning diagnostics and profile files are not committed or uploaded as CI logs.

## Separate manual-path incompatibility

After the successful automatic export, one bounded manual archive attempted to use the same cached profile and exact distribution identity. It failed with Xcode exit 65 before signing: the profile is Xcode managed, while the archive requested manual management. The profile’s signed metadata has `IsXcodeManaged = true`. This attempt is retained under root `build/store-signing-verification/` with its own `latest-provisioned-archive.json` pointer; it was not retried or relabeled as the automatic export.

The manual Actions driver now rejects a managed or malformed management marker before importing keys or archiving. General exported-app verification still accepts a valid managed Store profile. A focused regression covers this distinction and permits custom profiles with a missing/false marker. The optional manual pipeline needs a custom profile if selected; the working local automatic route needs no new owner profile action. Apple distinguishes [automatic and manual distribution signing](https://help.apple.com/xcode/mac/current/en.lproj/devff5ececf8.html). All 79 repository tests passed after the additional guard, along with configuration/link, actionlint and whitespace checks. Native CI remains pending.
