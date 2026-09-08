# Local Store signing identities — 2026-09-08 UTC

Release gate #14; setup documentation under implementation issue #52.
The publisher explicitly approved creating the two Store certificates, then
reported creating them directly in Xcode. Its certificate manager now displays
Apple Distribution and Mac Installer Distribution, both dated 2026-09-08.

## Verified local assets

| Check | Apple Distribution | Mac Installer Distribution |
| --- | --- | --- |
| Certificate team | `4T674XS5MF` | `4T674XS5MF` |
| Matching local private key | Present | Present |
| Valid from (UTC) | 2026-09-08 06:07:37 | 2026-09-08 06:07:20 |
| Expires (UTC) | 2027-09-08 06:07:36 | 2027-09-08 06:07:19 |
| Valid identity after intermediate addition | Yes | Yes |
| Actual signing use | Universal generated executable passed | Generated empty package passed |
| Trusted timestamp | Present on both architectures | Present |
| Exact selected certificate pin | Verified on both architectures | Verified |

The initial `security find-identity -v` check omitted both new identities.
The complete identity inventory showed their matching private keys and team,
but reported `CSSMERR_TP_NOT_TRUSTED`. Public-certificate inspection identified
WWDR G3 as their issuer. The available WWDR inventory contained only the older
intermediate that expired in 2023.

Downloaded WWDR G3 from the link on [Apple's PKI page](https://www.apple.com/certificateauthority/),
verified its subject, issuer, validity and chain to existing system trust, and
checked both leaf chains with that intermediate supplied explicitly. Its SHA-256
is `DCF21878C77F4198E4B4614F03D696D89C66C66008D4244E1B99161AAC91601F`;
it expires on 2030-02-20. Apple's [WWDR guidance](https://developer.apple.com/support/expiration/)
describes the required intermediate for software-signing certificates.

Added only that public intermediate with `security add-certificates` to the
login keychain. No root certificate or trust override was added; no existing
certificate was removed, no private key was exported, and keychain access rules
were not changed. Afterward both pinned certificates appeared as valid
certificate/private-key identities, and each leaf passed local basic-chain
verification without explicitly supplying the intermediate.

One diagnostic assertion initially assumed the opposite RFC2253 subject display
order; this was corrected before import. A separate generic `pkgSign` diagnostic
rejected the installer EKU. Its actual `1.2.840.113635.100.4.9` EKU and
`1.2.840.113635.100.6.1.8` role marker match Apple's
[third-party Mac distribution installer definitions](https://github.com/apple-oss-distributions/Security/blob/main/OSX/sec/Security/SecPolicy.c).
Basic chain validity is reported separately from package acceptance. No product
validation rule or trust setting was relaxed to produce a pass.

## Signing-use verification

The generated universal executable passed `codesign` verification with an Apple
anchor and team `4T674XS5MF`. Both arm64 and x86_64 signatures include Hardened
Runtime, a trusted timestamp and the selected Apple Distribution certificate.
Evidence: `signing-use-FB817135-8168-40D1-BAFE-778CD3AA798C/report.json` under
root `build/store-signing-verification/`. That report remains incomplete overall
because its later installer step timed out; each successful app check is retained.

A separate timestamped installer-only run then passed on 2026-09-08 at 06:43 UTC:
`installer-use-4EC50830-8FF2-48A2-A71D-9CE25AFE7687/report.json`.
`pkgbuild` signed with the pinned Mac Installer Distribution identity;
`pkgutil --check-signature` exited zero, reported the Apple chain and trusted
timestamp, and matched the selected leaf SHA-256. Expansion confirmed no payload
or scripts. Package SHA-256:
`b5b7fc049b6a87b9b55d72ef1075ec25434daaea9fddaec20cf0b99926a785a2`.
The package was never installed. Apple documents the role and native packaging
tools in [Packaging Mac software for distribution](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution).

The package tool labels this chain as an Apple-issued developer certificate with
the suffix `(Development)`. The actual pinned leaf is the Store installer role
verified above. An earlier local helper incorrectly required the unrelated words
`trusted by`; it failed after native signature verification had succeeded.
The corrected diagnostic requires the observed native status, successful native
verification and the same exact certificate pin. Production package checks were
unchanged. A sandbox-restricted read-only verification returned untrusted; the
normal macOS trust-service execution passed without a trust override.

## Failures retained and verifier fixes

The first timestamped codesign invocation timed out after 30 seconds. Its owned
process was stopped; the fixture retained only its linker ad-hoc signature.
The publisher confirmed that no keychain prompt appeared and requested continued
signing. No system authorization UI was inspected or handled. A subsequent
timestamp-free diagnostic proved key access but did not qualify timestamped
signing. Later timestamped signing passed. The cause of the initial app and
installer timeouts remains unproven; their incomplete reports were not overwritten.

Real native execution exposed two production verifier argument bugs, fixed in
`801f60ff6ea8963f82d6f6c1ac233edfcf0e8857`:

- The literal Apple/team requirement needs a leading `=` after `-R`; otherwise
  codesign reads it as a filename. The native `csreq` regression failed before
  the fix and passed afterward. The actual signed fixture passed the expected
  team requirement and rejected a different validly formatted team.
- The optional certificate-output prefix must be attached as
  `--extract-certificates=<prefix>`. A regression using only the installed
  codesign binary's public certificate failed with the separated argument and
  passed after the fix. Both fixture architecture certificates now extract and pin.

All **54 standalone repository tests** pass, including the native regressions.
Python compilation, workflow actionlint, configuration, relative links and
whitespace checks pass. No Swift or UI test pass is inferred from those results.
No signature, team, profile, trust or timestamp requirement was weakened.

All attempts remain in the ignored private evidence directory. Besides the two
successful records above, retained attempt suffixes are `62621EE1` (initial
codesign timeout), `08B4983B` (requirement parser failure), `E16AD495`
(certificate extraction failure) and `06536A1E` (installer status assertion).

A separate RFC 3161 request containing only a generated fixture digest received
a parseable Granted response from Apple's documented timestamp endpoint in
0.9298 seconds. This checks endpoint response, not the timestamp signature or
the codesign process's keychain access. The endpoint is taken from Apple's
[published timestamp configuration](https://github.com/apple-oss-distributions/Security/blob/main/OSX/lib/TimeStampingPrefs.plist).

## Remaining release scope

Root `build/store-signing-verification/` retains public certificate metadata,
exact fingerprints, intermediate preflight and post-addition identity results
with private file permissions. No signing credentials were committed or placed
in GitHub secrets. The two standard local provisioning-profile locations contain
no installed profiles. Resolve the explicit App ID and Store app record,
provisioning, final-source CI/review, signed NoteHush archive/export,
upload/processing and installed TestFlight acceptance before completing #14.
These checks used generated fixtures; no NoteHush release candidate was signed,
launched, installed or uploaded by them. Version remains `0.1.0 (1)` and no release
was published.

Follow-up: a [signed NoteHush engineering archive and local Store export](2026-09-08-local-signed-export.md)
subsequently passed signature and product checks. Their missing profile still
blocks TestFlight acceptance; this later result does not change the fixture scope above.
