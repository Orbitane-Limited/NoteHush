# Local signed archive and export — 2026-09-08 UTC

Engineering rehearsal for #14, with delivery fixes tracked under #52.
**Signing and export succeeded; TestFlight provisioning and release acceptance
remain incomplete.** Nothing was installed, launched, uploaded or published.

## Provenance and results

| Item | Evidence |
| --- | --- |
| App source | Clean integration commit `906712cd24e93dbfdc714970aae085f77b395a59` |
| Verification tools | `227cb4593f88e6121da5acf1a120b9e01ace9177`; no app/source/project/config difference from the build commit |
| Version / build | `0.1.0 (1)` |
| Publisher team | `4T674XS5MF` |
| Archive | Xcode Release archive succeeded, 06:45:55–06:46:31 UTC |
| Export | Xcode `app-store-connect`, destination `export`, succeeded 06:50:51–06:51:24 UTC |
| Application identity | Exact selected Apple Distribution certificate on arm64 and x86_64, both archive and exported app |
| Installer identity | Exported package passes native `pkgutil --check-signature` and exact Mac Installer Distribution SHA-256 pin |
| Permissions | Exactly sandbox, user-selected read/write, app-scoped bookmarks and printing on both architectures |
| Runtime and metadata | Hardened Runtime, universal binary, declared version/bundle/minimum OS, matching privacy manifest, original icon and encryption flag verified |
| Isolation | No test/performance/Undo diagnostic markers; no quarantine attributes |
| Provisioning | No embedded profile in archive or exported app; application/team identity entitlements are absent |
| Strict Store verifier | Correctly rejects the missing profile; no exception added |

The archive command used the production scheme, Release configuration, generic
macOS destination, manual signing and the exact local Apple Distribution SHA-1.
It requested a trusted timestamp. Export pinned that application certificate and
the Mac Installer Distribution certificate, disabled version/build management,
and did not permit provisioning updates. No new account asset or private-key
export was requested. The source is the integration branch, not reviewed main.

The archive has trusted timestamps on both architectures. Xcode's Store export
re-signed the app and package without timestamps. The inspection records that
difference; it does not claim the exported bytes retained the archive signatures.
The installed `productsign(1)` manual describes timestamps as optional and enabled
by default for Developer ID identities. Two initial diagnostic timestamp
assertions stopped inspection; recording the actual Store export behavior did
not change any production release requirement or re-sign the output.

Apple explains that a Mac app without restricted entitlements may be exported
without a profile, but **TestFlight always requires one**. This accounts for
Xcode's successful export and the deliberately stricter TestFlight pipeline's
rejection. See [TN3125](https://developer.apple.com/documentation/technotes/tn3125-inside-code-signing-provisioning-profiles)
and [TestFlight on Mac](https://developer.apple.com/videos/play/wwdc2021/10170/).

## Platform verification fix

Actual archive inspection exposed use of `os.listxattr`, which is not available
in this macOS Python build. Python documents those extended-attribute functions
as Linux facilities in its [OS interface](https://docs.python.org/3/library/os.html#linux-extended-attributes).
Issue #52 commit `90b05ce` replaces it with native read-only `xattr -s` name listing,
including the package path. It preserves no-follow behavior, rejects unreadable
inspection and never removes quarantine marks.

Three real filesystem regressions failed before the fix. The first implementation
then exposed an ordinary-file traversal error; the package regression caught it
and passed after correction. All **57 standalone repository tests** and **102
combined repository tests** now pass. Python compilation, configuration, relative
links and whitespace checks pass. Logs: `quarantine-native-before.log`,
`quarantine-native-after.log`, `quarantine-native-final.log` in issue #52's
`build/logs/`; `combined-store-quarantine-repository.log` in the integration.

An earlier combined run of the preceding code failed its native public-certificate
extraction under the tool sandbox: codesign returned zero but produced no leaf.
The same 99 tests passed with normal macOS signing-service access. Its failed log
is retained; no test was skipped or changed to accept missing certificates.

## Retained artifacts and remaining work

Root `build/store-signing-verification/` contains private, ignored evidence:

- `local-archive-FEB659BB-2ED0-42EC-B745-3A3953BFF36C/`: archive, private build log,
  `report.json` and `verification.json`. Executable SHA-256:
  `bd439cb2da2279ca4c694f7bd8d9e65c917dc1e44fc646af3bb84716cf88311c`.
- `local-export-88498845-B540-4344-B66B-35FB165A1423/`: original export, expanded
  inspection copies, private export log and reports. Package SHA-256:
  `b024b1b7dfb73b07e5db9c6bf60a73fe67ba9e26f86345b6dc4e71837a76e519`.
  Exported executable SHA-256:
  `3d7560958242431ebd5f150dd9b4821c4ded071aaf325f7d5f619dec7ac3c99f`.

The publisher has been asked to generate/download a Mac App Store Connect profile
for the explicit `pk.codehub.NoteHush` App ID and selected Apple Distribution
certificate. Follow [Apple's profile instructions](https://developer.apple.com/help/account/provisioning-profiles/create-an-app-store-provisioning-profile/).
Validate that profile and rebuild/export before claiming TestFlight compatibility.
App record, final-source CI/review, Apple upload validation, processing, installed
TestFlight and all remaining manual/hardware gates still apply. Keep #14 open.
