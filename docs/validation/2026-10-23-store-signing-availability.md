# Store signing identity availability

Date: 2026-10-23. Issue #52 / release gate #14.

The first read-only check from the automation shell found no local identities. The publisher then supplied a screenshot of Keychain Access and output from their interactive Terminal. The `login` keychain's My Certificates view shows both the `Apple Distribution` certificate and its private key, and the `3rd Party Mac Developer Installer` certificate and its private key. The publisher's `security find-identity -v` output reports 10 valid identities, including both team identities; the repeated entries share fingerprints and do not represent additional distinct certificates.

The publisher initially used `security find-identity -v -p codesigning`, which intentionally filters installer identities out. Apple's [packaging guide](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution) identifies `3rd Party Mac Developer Installer: <Team>` as the Mac App Store installer identity and says to run `security find-identity -v` without the `codesigning` filter. The delivery verifier accepts this identity name.

The automation shell still reports zero identities. Its keychain/security context differs from the publisher's interactive Terminal; this does not contradict the publisher's local evidence. The guarded Actions delivery imports its signing assets into a temporary keychain, so its own protected-secret preflight remains the relevant CI check. No private key, password, or PKCS#12 content was read, changed, exported, or committed by the agent.

The successful signed archive/export recorded in [the September rehearsal](2026-09-08-local-signed-export.md) remains valid evidence for that exact earlier source and artifact. It does not validate a reviewed `main` candidate. Although the publisher's interactive login keychain contains both identities, no current-source archive, upload, or TestFlight operation was attempted in this validation.
