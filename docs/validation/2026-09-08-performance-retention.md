# Failed performance-fixture retention

Date: 2026-09-08. Issue #57. Base: main `2c786fac01a59e548475c20f985050c0a430e992`. This corrects the host validation scripts, not shipping app persistence or the cause of prior unexpected input.

The launch and attached-profile drivers previously installed unconditional EXIT cleanup after fixture preparation. A later failed test, recovery check, metric extraction or profiler could therefore remove the generated manifest and recovery generations needed for diagnosis. Retained `.xcresult`/trace files do not replace the original recovery evidence.

Both drivers now call a shared exit handler with the original exit status and the existing cleanup command as separate quoted arguments. A failed or interrupted status is returned unchanged, with no fixture cleanup call. Only complete script success invokes cleanup; its own failure becomes the script's failure. The handler disables its EXIT trap before exiting, so it cannot recurse. The existing UUID isolation and stopped-app requirement remain in the host helper; the shell handler never enumerates or terminates processes. Preparation failure still cannot acquire or delete a previous run's fixtures.

## Regression evidence

The same six tests run the actual shell-driver control flow with fake native executables and disposable generated files. Before the script correction, they exposed **12 failing subcases**, all showing an unwanted cleanup call after an injected failure. The complete-success, cleanup-failure and failed-acquisition protections already passed. After the correction, all six tests pass unchanged.

Cases cover environment capture, native test exit, sandbox verification, recovered-buffer verification, both metric export paths, summary validation, profiler failure, post-profile verification and statuses 130/143. The latter verify interrupted exit handling; no claim of real OS signal delivery is made. Success cleans exactly once after the final required stage, cleanup failure returns its own nonzero status, and failed fixture acquisition preserves preexisting generated data. No native tool, NoteHush process, regular recovery workspace or user note is touched by these tests.

All 34 repository tests pass, along with shell syntax, configuration/relative-link and diff checks. Private before/after logs are retained as `build/logs/retention-before.log` and `retention-after.log`, with the complete repository result in `retention-repository-final.log`. Assertions, functional timeouts, fixture sizes, sample counts and timing boundaries are unchanged. No Swift/runtime source changed, so prior app-build results are not relabeled as new native validation. Full final-head CI/review and #29 native input attribution remain pending.

The final retention PR depends on #49 (storage checks) and #44 (the interaction protocol). Its prepared branch includes those related dependencies and now applies the same exit handling to all three drivers. Merge both dependency PRs into main first, then verify this PR’s diff contains only retention changes before merging it. Any previously removed fixture cannot be reconstructed by this fix; retained overnight evidence remains untouched.


## Prepared dependency integration — 2026-09-08 UTC

Current main `94ad233` includes the passing hidden-editor correction. The prepared retention branch also includes the reviewed storage and interaction dependency heads. The interaction driver uses the shared exit handler, and the same six retention regressions now exercise both launch/interaction drivers plus attached profiling.

The first integrated run executed 47 repository tests. Its only failed test had three subcases: the storage-after-build fixture had not copied the newly sourced exit helper, so each script stopped before its second capacity check. Copying the real helper into that disposable fixture restores the intended scenario. All seven storage tests then passed, including the unchanged assertion that capacity is checked twice and no fixture is launched after the second check fails. The other 40 repository tests had already passed. Configuration, shell syntax and diff checks pass. Full final-head CI remains required; no native app was launched by these offline tests.

The complete integrated repository suite was subsequently rerun after that fixture correction: **47 tests passed**, with no failures, in 46.733 seconds. The full log is retained privately at `build/logs/integrated-retention-final-repository.log`. This covers all three actual shell drivers; native CI remains a separate gate.
