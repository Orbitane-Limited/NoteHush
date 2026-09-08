# Self-hosted runner operations

The owner requested this Mac as NoteHush's CI host on 2026-09-06. Current runner scope: **Orbitane-Limited/NoteHush only**, following the repository transfer from CodeHubdotPk. Name: `NoteHush-Mac-arm64`. Labels: `self-hosted`, `macOS`, `ARM64`, `notehush`, `xcode-26.6`.

Installation directory: `~/Library/NoteHushActionsRunner` (user-only access). Job checkouts live under its `_work` directory, separate from the development checkout. The official GitHub runner 2.337.0 arm64 package was selected through GitHub's runner download API; verify its published SHA-256 before extraction. Runner auto-update remains enabled. Registration tokens are short-lived and must never be committed or pasted into issues.

The per-user launchd service starts at login. The Mac must remain awake, logged in, unlocked and connected; sleeping/offline pauses availability and jobs queue. GUI tests require the unlocked desktop and may briefly bring NoteHush's isolated fixture window forward. No sleep settings are changed automatically. Only one job runs at a time. GitHub remains the source of run logs, status checks and retained artifacts.

## Service commands

```sh
cd "$HOME/Library/NoteHushActionsRunner"
./svc.sh status
./svc.sh stop
./svc.sh start
```

To remove later, stop/uninstall the service, remove the runner registration through repository Settings > Actions > Runners, and only then remove its dedicated directory. Do not delete the development checkout. Logs are under `_diag`; treat them and `.credentials*` as private.

## Tooling and isolation

Xcode: `/Applications/Xcode.app`, initially 26.6 (17F113). `scripts/check.sh` verifies the selected version. Python 3, Bash and the Xcode tools are required; the committed project avoids a runtime XcodeGen dependency. Keep macOS/Xcode and runner patched, and update the documented toolchain through an issue/PR.

This is a persistent runner executing as the logged-in Mac user, not a disposable VM. Keep the repository private and grant push/workflow access only to trusted collaborators. The workflow skips PRs from forks; that guard is not a security boundary against someone permitted to edit workflow files. Do not enable untrusted fork workflows or use `pull_request_target` to execute PR code. Signed delivery gets a separate environment in M6; current jobs receive no signing secrets. Checkout does not persist GitHub credentials.

Branch protection is unavailable under the current private-repository plan, so observing checks and reviewing workflow changes remains procedural. Monitor disk use in `_work` and artifact retention. Do not remove a work directory while the runner reports `busy: true`.

Verified on 2026-09-07: the canonical repository API reports the existing runner online and serving CI. Its service registration and credentials were retained. The new owner's branch-protection endpoint still returns HTTP 403 with the private-plan upgrade requirement. Keep requiring green checks and resolved review before manual squash merges; do not change repository visibility or add an impossible self-approval rule to simulate enforcement.

Check current availability through the canonical scope:

```sh
gh api repos/Orbitane-Limited/NoteHush/actions/runners --jq '.runners[] | {name,status,busy}'
```

## Disk headroom and retained evidence

CI, engineering delivery and performance workflows run `python3 scripts/check_runner_storage.py` before native work. The full check, standalone app-test/archive/performance-build scripts and measurement/profile scripts also enforce it for local invocations. Measurement/profile and app-test scripts check again after building before launching fixtures. Before a manual Xcode command, run the same preflight yourself.

Both the workspace and temporary-file filesystem must have at least **20 GiB and 10% of total capacity**, whichever requires more available bytes. This is NoteHush's engineering headroom policy, not an Apple-defined purge threshold or a guarantee against later resource pressure. Capacity uses currently available bytes, without counting hypothetical purgeable storage. Unreadable/invalid capacity or inability to retain the report fails the gate. There is no bypass flag. Each invocation writes a fresh `build/logs/runner-storage-<UUID>.json` with time, capacity, requirement and result; it records no user/device names or document paths. Workflows retain these reports even when preflight stops validation.

The policy follows confirmed macOS `0xBADDD15C` cache-reclamation terminations of NoteHush's UI runner; see [the investigation](validation/2026-09-07-runner-storage.md). A failed preflight is an infrastructure failure, not a passing/skipped test suite. After restoring headroom, require complete exact-head validation and assess any remaining UI failures separately. Do not retry unchanged native tests while the known storage condition persists.

Cleanup is never automatic. Completed NoteHush checkouts' ignored compiler caches (`ModuleCache.noindex`, `Build/Intermediates.noindex`, `Index.noindex`, `SDKStatCaches.noindex` inside their DerivedData directories) can be regenerated after confirming no process uses that checkout. Keep `Build/Products`, `Logs`, `.xcresult`, traces, archives, recorded metrics and failed recovery evidence. Do not remove the active runner checkout, normal app storage, unknown UUID fixtures, unrelated project caches or user files. If this bounded cleanup is insufficient, the operator must free additional storage before native validation resumes.

## References

- [GitHub: add a self-hosted runner](https://docs.github.com/en/actions/how-tos/manage-runners/self-hosted-runners/add-runners)
- [GitHub: runner service management](https://docs.github.com/en/actions/how-tos/manage-runners/self-hosted-runners/configure-the-application)
