# Signing child environment review

Issue #52 preparation, 2026-09-08 UTC. Before this follow-up, native delivery
tools inherited every parent environment value except `STORE_*`, `GH_TOKEN` and
`GITHUB_TOKEN`. That excluded known signing inputs but still passed unrelated
service credentials and executable/configuration overrides to native children.
No real credential was inspected, printed or used during this review.

The child environment now permits only `PATH`, `HOME`, `TMPDIR`, `USER`, `LOGNAME`,
`DEVELOPER_DIR`, `LANG` and `__CF_USER_TEXT_ENCODING`, forcing `LC_ALL=C`.
Missing values stay missing. The delivery driver explicitly supplies its owned
upload key directory when invoking the uploader. The parent retains the variables
needed for GitHub preflight and signing asset setup. This is an environment
propagation boundary, not isolation from malicious source or a compromised runner.

Two new regression cases failed before the change: the exact environment fixture
contained undeclared inputs, and a real harmless child could still read a generated
unrelated credential. Both pass afterward without changing their assertions. The
full issue-branch repository suite passes **48 tests**, including real OpenSSL JWT
verification and simulated signing ownership, cancellation and cleanup failures.
Configuration, relative links and whitespace checks pass. With the restricted
environment, local `xcodebuild -version` reports Xcode 26.6 / 17F113 and `xcrun`
resolves the system `codesign`; neither command signs or launches the app.

Private local logs are `build/logs/tool-environment-before.log` and
`build/logs/tool-environment-after.log`. Tests use invented credential strings.
No native input, keychain change, profile installation, signed archive, upload or
TestFlight acceptance ran. The local Organizer path is documentation checked
against Apple's published instructions, not evidence that its steps succeeded.


The follow-up audit also found that the source preflight's `gh` and `git`
children still inherited the full parent environment when the signing driver
rechecked the source. They now use the same allowlist; only `gh` receives the
explicit workflow token, and a missing token fails before invoking it. Local Git
receives no token. These calls have bounded 60/30-second timeouts. Three additional
mocked subprocess regressions failed before this correction and pass afterward;
the full standalone suite now passes **51 tests**. No GitHub account credentials
or signing assets were used by those tests. The preflight authorization gates and
required human environment review are unchanged.


The installed uploader's local `altool --help` completed successfully with the
restricted environment. It confirms this driver's `--validate-app <filepath>`,
`--upload-package <filepath>`, `--api-key`, `--api-issuer` and owned-key lookup
syntax. Help inspection performed no authentication or upload; it does not
validate Apple's server-side acceptance of a candidate. The initial sandboxed
help invocation failed without a usable result; the read-only tool inspection
outside that sandbox succeeded. No system permission or account setting changed.

## Publisher team confirmation

On 2026-09-08 UTC the publisher explicitly confirmed Apple Developer team
`4T674XS5MF`. A fresh read-only `security find-identity -v` check, with the same
restricted child environment, counted the valid local identities matching that
team without printing certificate holder names or exporting private keys:

| Identity role | Valid local identities |
| --- | ---: |
| Apple Distribution or Mac App Distribution | 0 |
| Mac Installer Distribution | 0 |
| Developer ID Application | 1 |
| Apple Development or Mac Development | 0 |

This is a local availability check, not a remote certificate inventory or proof
of authenticated Xcode/App Store Connect access. A Developer ID Application
certificate is for distribution outside the Mac App Store; Apple's
[certificate roles](https://developer.apple.com/help/account/certificates/certificates-overview)
distinguish it from Store application and installer identities. No certificate,
keychain, profile, account or repository secret was changed.

The confirmed value is recorded as `STORE_TEAM_ID` in the delivery setup. The
separately supplied membership Developer ID was not mapped to an App Store
Connect API issuer or app ID. Seller, explicit App ID, Store app record, Store
signing assets and live delivery remain pending under #14. Team confirmation
does not complete that issue's combined publisher/account acceptance criterion.

The subsequent read-only Xcode account inspection found an existing Apple
account, an Admin team with Certificates, Identifiers & Profiles access, and a
certificate manager showing Developer ID Application. The creation menu offers
Apple Distribution and Mac Installer Distribution. The menu was cancelled
without choosing either entry; the certificate manager remains open. No new
login, credential creation, private-key export, profile download or account
setting change occurred. This verifies the available Xcode setup interface,
not a signed account transaction or App Store Connect app access. The account
UI did not display a team ID, so any resulting signing assets must still be
checked against the publisher-confirmed `4T674XS5MF` before use.
