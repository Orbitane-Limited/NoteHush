# Failed performance-fixture retention

Date: 2026-09-08. Issue #57. Base: main `2c786fac01a59e548475c20f985050c0a430e992`. This corrects the host validation scripts, not shipping app persistence or the cause of prior unexpected input.

The launch and attached-profile drivers previously installed unconditional EXIT cleanup after fixture preparation. A later failed test, recovery check, metric extraction or profiler could therefore remove the generated manifest and recovery generations needed for diagnosis. Retained `.xcresult`/trace files do not replace the original recovery evidence.

Both drivers now call a shared exit handler with the original exit status and the existing cleanup command as separate quoted arguments. A failed or interrupted status is returned unchanged, with no fixture cleanup call. Only complete script success invokes cleanup; its own failure becomes the script's failure. The handler disables its EXIT trap before exiting, so it cannot recurse. The existing UUID isolation and stopped-app requirement remain in the host helper; the shell handler never enumerates or terminates processes. Preparation failure still cannot acquire or delete a previous run's fixtures.

## Regression evidence

The same six tests run the actual shell-driver control flow with fake native executables and disposable generated files. Before the script correction, they exposed **12 failing subcases**, all showing an unwanted cleanup call after an injected failure. The complete-success, cleanup-failure and failed-acquisition protections already passed. After the correction, all six tests pass unchanged.

Cases cover environment capture, native test exit, sandbox verification, recovered-buffer verification, both metric export paths, summary validation, profiler failure, post-profile verification and statuses 130/143. The latter verify interrupted exit handling; no claim of real OS signal delivery is made. Success cleans exactly once after the final required stage, cleanup failure returns its own nonzero status, and failed fixture acquisition preserves preexisting generated data. No native tool, NoteHush process, regular recovery workspace or user note is touched by these tests.

All 34 repository tests pass, along with shell syntax, configuration/relative-link and diff checks. Private before/after logs are retained as `build/logs/retention-before.log` and `retention-after.log`, with the complete repository result in `retention-repository-final.log`. Assertions, functional timeouts, fixture sizes, sample counts and timing boundaries are unchanged. No Swift/runtime source changed, so prior app-build results are not relabeled as new native validation. Full final-head CI/review and #29 native input attribution remain pending.

The new interaction driver is still in pending #43 rather than main. When integrating that branch, wire its EXIT handling to the same helper and exercise the same failure-retention policy; do not copy the unmerged interaction implementation into this issue branch. Any previously removed fixture cannot be reconstructed by this fix. Failed evidence already retained from the overnight manual diagnostics remains untouched.
