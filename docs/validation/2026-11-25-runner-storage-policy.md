# Runner storage reserve update — 2026-11-25

## Decision

Native validation now requires a fixed **20 GiB of currently available space** on both the workspace filesystem and the temporary-file filesystem. The reserve no longer scales with filesystem capacity. The preflight continues to fail closed for invalid or unreadable capacity and for failures to retain its report; it has no bypass or automatic cleanup.

## Rationale

The prior 10%-or-20-GiB formula blocked native work on a large volume even when the machine had substantially more space than the project's observed cache-reclamation failure point. The confirmed NoteHush UI-runner terminations occurred around 14.6 GiB available ([investigation](2026-09-07-runner-storage.md)). A fixed 20 GiB reserve keeps roughly 5.4 GiB above that observed point without requiring tens of gigabytes solely because the volume is large.

That margin is an engineering choice based on observed runs, not an Apple guarantee, a universal safe-space threshold, or proof that future builds cannot encounter resource pressure. The preflight reports actual currently available bytes; it does not count purgeable storage. If native work fails with storage pressure above the reserve, preserve the failure evidence and revise the policy using the new measurements.

## Regression coverage

Repository tests verify below/at/above the fixed 20 GiB boundary on both a 100 GiB and a greater-than-1 TiB sample volume. They also cover invalid and unreadable capacities, per-volume failure, retained reports, report-write failure, and fail-fast behavior before native commands. No test fills a real filesystem.

## Validation record

Record the focused test result and actual workspace/temporary preflight report with the PR that applies this policy. Native build/test results remain subject to the ordinary storage preflight and are not implied by this policy decision.
