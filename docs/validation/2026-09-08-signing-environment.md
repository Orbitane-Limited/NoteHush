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
