# Store delivery preparation — 2026-09-08

Implementation sub-issue: #52; parent release gate: #14. Implementation commit: `5c40f984f20857e0fbb13431cd0b4d212af046e5`, branch `issue-52/app-store-delivery`, based on main `2c786fac01a59e548475c20f985050c0a430e992`. This branch was renamed from `issue-14/app-store-delivery` when implementation and live distribution acceptance were separated. Its code and recorded validation are unchanged. Local date is 2026-09-08 in Asia/Karachi; execution occurred on 2026-09-07 UTC.

## Prepared behavior

A separate manual Store workflow checks the exact current main commit, the complete successful CI run and configured environment reviewers before its signing job receives secrets. It imports supplied identities into a temporary keychain, preserves unrelated profiles/keychains, builds and validates a universal archive, exports and inspects the actual package, checks all prior App Store build numbers, then validates/uploads with Apple's installed tool. It never submits App Review or publishes a GitHub release. See [the setup and operating protocol](../APP_STORE_DELIVERY.md).

This is an implementation candidate, not a completed signing/TestFlight gate. The app code and engineering version `0.1.0 (1)` are unchanged. No native GUI tests, app launches, certificate creation, private-key export, account mutation or upload were performed for this preparation.

## Executed checks

| Check | Result | Scope |
| --- | --- | --- |
| Repository automation suite | 46 tests passed | Existing automation plus Store source/environment, version, profile, permission, pagination and cleanup failure cases |
| Real disposable OpenSSL key | Passed | OpenSSL independently verifies the generated ES256 JWT signature; expiry and app-specific GET scope are checked |
| Credential ownership/cleanup fixtures | Passed | Owned assets removed, existing/replaced profiles preserved, unrelated keychains retained, partial cleanup retried, plaintext credentials removed when keychain deletion fails |
| actionlint 1.7.12 | Passed | New workflow parsed against official actionlint with the Mac's existing custom runner labels declared |
| Python compilation | Passed | All four new delivery modules |
| Configuration, documentation links, whitespace | Passed | Existing configuration validator and `git diff --check` |
| Existing unsigned Release archive | Correctly rejected | Used the retained issue #29 unsigned artifact; no embedded Store profile, no signing result claimed |
| Local delivery preflight without GitHub context | Correctly rejected | Stops before any signing asset access |

Commands:

```sh
python3 -m unittest discover -s Tests/RepositoryAutomationTests -v
build/tools/actionlint/actionlint -shellcheck= -pyflakes= .github/workflows/app-store.yml
python3 -m py_compile scripts/app_store_checks.py scripts/store_connect.py scripts/store_delivery.py scripts/store_preflight.py
python3 scripts/verify_configuration.py
git diff --check
```

The initial actionlint invocation flagged the two existing custom runner labels as unknown. Adding `.github/actionlint.yaml` with those actual labels resolved it. ShellCheck and pyflakes are not installed; their optional integrations were disabled, and neither was claimed as run. The workflow's run steps invoke the validated Python entry points. The downloaded official `actionlint_1.7.12_darwin_arm64.tar.gz` matched the GitHub release asset SHA-256 `aba9ced2dee8d27fecca3dc7feb1a7f9a52caefa1eb46f3271ea66b6e0e6953f` before execution; the binary is local tooling, not a tracked runtime dependency.

Local evidence remains ignored under this worktree's `build/logs/`: `store-repository-tests.log`, `store-actionlint.log`, `store-negative-archive.json` and `store-local-gate-rejection.txt`. The negative archive check used a previously built unsigned binary; it is not a new build of this pipeline or independent evidence that signed validation passes.

## Gates still open

- Publisher team/bundle confirmation; matching App ID and App Store Connect app record.
- Available GitHub environment protection and real reviewer setup, with settings checked and required secrets configured. No claim that source YAML enables remote protection.
- Actual Store application/installer identities and profile. The observed installed Developer ID Application identity does not qualify.
- Real archive/export/signature/profile/entitlement validation and real cleanup on this Mac with signing assets. Fixture tests do not substitute for those operations.
- Complete successful CI for the merged release source, successful Apple processing, installed TestFlight fresh/upgrade acceptance, production sandbox lifecycle/files/printing, hardware/OS, accessibility/IME and performance evidence.
- Public store materials and remaining v1 acceptance, App Review and release gates.

No issue was closed, no branch was merged and no release was created based on these checks. A PR has not yet been opened because this repository's PR event immediately starts the native self-hosted CI suite, whose exclusive-input window remains pending.
