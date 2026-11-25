# CI runner policy and historical self-hosted setup

**Current policy, 2026-11-25:** NoteHush uses GitHub-hosted `macos-26` for all Actions workflows. The offline `NoteHush-Mac-arm64` repository runner was deregistered after the repository became public. Do not install a persistent runner or route workflows to its former labels. The remaining sections retain the setup history and the current native-test, storage and artifact policies; any former runner service commands and cache paths are historical only.

Historically, the owner requested this Mac as NoteHush's CI host on 2026-09-06. Required pull-request and main-branch CI moved to GitHub-hosted `macos-26` after the repository became public. The repository is **Orbitane-Limited/NoteHush**, transferred from CodeHubdotPk and made public on 2026-10-23. The former runner was named `NoteHush-Mac-arm64` and used labels `self-hosted`, `macOS`, `ARM64`, `notehush`, and `xcode-26.6`.

Installation directory: `~/Library/NoteHushActionsRunner` (user-only access). Job checkouts live under its `_work` directory, separate from the development checkout. The official GitHub runner 2.337.0 arm64 package was selected through GitHub's runner download API; verify its published SHA-256 before extraction. Runner auto-update remains enabled. Registration tokens are short-lived and must never be committed or pasted into issues.

The per-user launchd service starts at login. The Mac must remain awake, logged in, unlocked and connected; sleeping/offline pauses availability and jobs queue. GUI tests require the unlocked desktop and may briefly bring NoteHush's isolated fixture window forward. No sleep settings are changed automatically. Only one job runs at a time. GitHub remains the source of run logs, status checks and retained artifacts.

## UI automation authorization

Before unattended XCTest UI work, run `python3 scripts/check_ui_automation.py` in the same login/service context that will start the tests. The app-test, launch-measurement and interaction-measurement scripts call it before preparation and again after builds. It reads `/usr/bin/automationmodetool` with no arguments, using a five-second bound. An enabled Automation Mode, or a host configured to enable it without authentication, passes this prerequisite. Disabled mode with required administrator authentication fails before fixtures or native tests start. Unknown status or a failed read also fails; no assertion, timeout or signing permission changes.

The installed Apple `automationmodetool(1)` manual describes its unattended CI configuration. The Mac owner may run `sudo /usr/bin/automationmodetool enable-automationmode-without-authentication` to permit UI-testing Automation Mode without repeated administrator authentication; the inverse command is `sudo /usr/bin/automationmodetool disable-automationmode-without-authentication`. These are security-policy choices for the owner, never commands run by this preflight or CI. They do not replace the separate accessibility permission described in [Apple's UI automation documentation](https://developer.apple.com/documentation/xcuiautomation/recording-ui-automation-for-testing), an unlocked desktop or exclusive input. Do not edit TCC databases or dismiss unidentified authorization dialogs.

The manually dispatched **Hosted Automation Mode status** workflow reports the ephemeral `macos-26` job's setting only. It does not query this Mac and cannot resolve differences between Terminal and another local shell. Run `python3 scripts/check_ui_automation.py` in the same local context that will start tests; neither result changes authorization or substitutes for an awake, unlocked desktop and exclusive input.

The [2026-09-08 startup failure](validation/2026-09-08-automation-startup.md) records the former local runner's disabled/authentication-required state separately from older unexplained input changes. Historic queued runs and the removed `notehush` label do not describe current runner availability. Current Actions jobs use GitHub-hosted `macos-26`; a local Automation Mode failure only prevents local native UI tests.

## Former runner decommissioning

On 2026-11-25, GitHub reported zero repository runners. The former launch agent was unloaded after `launchctl` reported it was not running; the dedicated `~/Library/NoteHushActionsRunner` installation, its launch-agent plist and its runner-only log directory were then removed. The development checkout and personal files were preserved. No NoteHush runner service remains to start or stop.

## Tooling and isolation

Current hosted image: Xcode 26.6 at `/Applications/Xcode_26.6.app/Contents/Developer`; `scripts/check.sh` verifies the selected version. Python 3, Bash and the Xcode tools are required; the committed project avoids a runtime XcodeGen dependency. Update the documented toolchain through an issue/PR.

While configured, the former runner executed as the logged-in Mac user rather than a disposable VM. The repository is public; CI skips pull requests from forks. That guard is not a security boundary against someone permitted to edit workflow files. Current workflows use GitHub-hosted VMs. Only the main-only signed delivery job can receive Store credentials after its protected environment gate; pull-request workflows receive none. Checkout does not persist GitHub credentials.

The repository is now public, so verify which free-plan branch protection options are available and configure required pull-request checks before relying on them. Until configured, observe checks and review workflow changes procedurally. Monitor disk use in `_work` and artifact retention. Do not remove a work directory while the runner reports `busy: true`.

Verified on 2026-09-07: the canonical repository API reported the existing runner online and serving CI. Its service registration and credentials were retained. The private-plan branch-protection request returned HTTP 403 at that time. Keep requiring green checks and resolved review before manual squash merges; do not add an impossible self-approval rule to simulate enforcement.

Check current availability through the canonical scope:

```sh
gh api repos/Orbitane-Limited/NoteHush/actions/runners --jq '.runners[] | {name,status,busy}'
```

## Disk headroom and retained evidence

CI, engineering delivery and performance workflows run `python3 scripts/check_runner_storage.py` before native work. The full check, standalone app-test/archive/performance-build scripts and measurement/profile scripts also enforce it for local invocations. Measurement/profile and app-test scripts check again after building before launching fixtures. Before a manual Xcode command, run the same preflight yourself.

Both the workspace and temporary-file filesystem must have at least **20 GiB of currently available space**, regardless of filesystem size. This is NoteHush's fixed engineering reserve, not an Apple-defined purge threshold or a guarantee against later resource pressure. Capacity uses currently available bytes, without counting hypothetical purgeable storage. Unreadable/invalid capacity or inability to retain the report fails the gate. There is no bypass flag. Each invocation writes a fresh `build/logs/runner-storage-<UUID>.json` with time, capacity, requirement and result; it records no user/device names or document paths. Workflows retain these reports even when preflight stops validation. See the [policy update](validation/2026-11-25-runner-storage-policy.md).

The policy follows confirmed macOS `0xBADDD15C` cache-reclamation terminations of NoteHush's UI runner; see [the investigation](validation/2026-09-07-runner-storage.md). A failed preflight is an infrastructure failure, not a passing/skipped test suite. After restoring headroom, require complete exact-head validation and assess any remaining UI failures separately. Do not retry unchanged native tests while the known storage condition persists.

Cleanup is never automatic. Completed NoteHush checkouts' ignored compiler caches (`ModuleCache.noindex`, `Build/Intermediates.noindex`, `Index.noindex`, `SDKStatCaches.noindex` inside their DerivedData directories) can be regenerated after confirming no process uses that checkout. Keep `Build/Products`, `Logs`, `.xcresult`, traces, archives, recorded metrics and failed recovery evidence. Do not remove the active runner checkout, normal app storage, unknown UUID fixtures, unrelated project caches or user files. If this bounded cleanup is insufficient, the operator must free additional storage before native validation resumes.

## Actions artifact storage

Successful pull-request validation streams its output to the Actions job log and does not upload the full `build/logs/` directory. A failed or cancelled CI run uploads that complete directory for seven days so reviewers can inspect the original `.xcresult` bundles and logs. CI runs on an ephemeral GitHub-hosted VM, so its local fallback is not durable if upload fails. The unsigned archive is uploaded for seven days only from a successful `main` CI run or the guarded delivery workflow. The opt-in performance workflow retains its raw measurement bundles for seven days on all outcomes because those bundles are the primary measurement evidence. Earlier self-hosted runs copied logs and generated fixture manifests to a private per-run fallback under the former runner directory. That path is historical; all current Actions jobs use ephemeral GitHub-hosted VMs. Upload and fallback errors remain failures; no tests or assertions are skipped to accommodate storage limits.

The largest observed verification-log artifact was 158,981,471 bytes. At that size, twelve failed pull-request runs retained for seven days would accrue about 299 GiB-hours, compared with GitHub Free for organizations’ 500 MB Actions/Packages shared allowance converted to about 372 GiB-hours per 31-day cycle ([GitHub Actions billing](https://docs.github.com/en/billing/concepts/product-billing/github-actions)). This is a planning scenario, not a hard storage guarantee: repeated runs, larger result bundles or Packages usage can exceed the allowance. Check billing usage and budgets before a release-validation batch; public standard runners are free, but confirm artifact upload behavior after the repository visibility change.

## References

- [GitHub: add a self-hosted runner](https://docs.github.com/en/actions/how-tos/manage-runners/self-hosted-runners/add-runners)
- [GitHub: runner service management](https://docs.github.com/en/actions/how-tos/manage-runners/self-hosted-runners/configure-the-application)
