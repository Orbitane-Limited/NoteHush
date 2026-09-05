# Self-hosted runner operations

The owner requested this Mac as NoteHush's CI host on 2026-09-06. Runner scope: **CodeHubdotPk/NoteHush only**. Name: `NoteHush-Mac-arm64`. Labels: `self-hosted`, `macOS`, `ARM64`, `notehush`, `xcode-26.6`.

Installation directory: `~/Library/NoteHushActionsRunner` (user-only access). Job checkouts live under its `_work` directory, separate from the development checkout. The official GitHub runner 2.337.0 arm64 package was selected through GitHub's runner download API; verify its published SHA-256 before extraction. Runner auto-update remains enabled. Registration tokens are short-lived and must never be committed or pasted into issues.

The per-user launchd service starts at login. The Mac must remain awake, logged in and connected; sleeping/offline pauses availability and jobs queue. No sleep settings are changed automatically. Only one job runs at a time. GitHub remains the source of run logs, status checks and retained artifacts.

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

## References

- [GitHub: add a self-hosted runner](https://docs.github.com/en/actions/how-tos/manage-runners/self-hosted-runners/add-runners)
- [GitHub: runner service management](https://docs.github.com/en/actions/how-tos/manage-runners/self-hosted-runners/configure-the-application)
