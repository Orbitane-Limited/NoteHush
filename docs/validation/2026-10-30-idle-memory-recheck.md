# Physical Mac memory recheck, 2026-10-30

Issue #67 remains open. These generated-fixture attempts do not produce an accepted allocation trace or a complete RSS/physical-footprint result. They change no application source and do not close the memory budget gate.

## Allocations profile

The clean source was `0cbb8d74805c9811495bec94ec16ef8241a9da45`. The optimized arm64 performance app passed the exact product sandbox signature check before launch. Its executable SHA-256 was `47fda51d3a69e43e726f3719b0dde957177be4f5782c3e79b99e2edb90fbc077`. The generated empty-workspace app was active after the protocol's 30-second settling interval.

The fixed 60-second Instruments Allocations recording did not attach to the exact process. `xctrace` reported `Failed to attach to target process` and exited with status 2. The resulting 18 MiB `.trace` bundle contains no usable allocation samples; no statistics or malloc-history export was produced, and the 20-tab fixture was not profiled. The source, fixture manifest, environment record, trace bundle and complete command output remain in `build/logs/Allocations-01261EBB-DD45-4D2D-A1C7-180CEB2618CB/`. The capture log SHA-256 is `0d20218639112c846808ee8ee0675e6a43835832f1b02524ac9593971cbac92f`.

The only filtered system diagnostic for that process was that `xctrace` could not obtain a symbol provider; it did not identify why attach failed. The cause is unknown. This run is retained as a failed instrumentation attempt, not a memory result.

## RSS and physical-footprint collection

The separate idle-resource protocol started from the same clean source and prepared generated empty and 20-tab/five-MiB workspaces. It collected 37 empty-workspace records after the 30-second settling period. On record index 36, `applicationActive` changed from `true` to `false` at about 37.58 seconds. The collector retained the partial JSONL, stopped the identified app process and exited with `inactiveApp`.

Because the run did not collect all 61 active samples, finish normal termination, independently verify recovery, or enter the second workload, it has no valid summary and cannot assess either the unchanged 80/150 MiB RSS budgets. The partial samples are not reported as a pass, a budget result, or a complete measurement. They remain in `build/logs/Idle-2B0830A7-F6EF-4D6F-A33F-87E0ED0631EA/`; the partial JSONL SHA-256 is `f1de596500f51cf5f0296a2777501e506fc470756af6fa6ec5d1c943ed8cfbc3`.

## Conditions and next action

Both runs used generated fixture data only, a fresh optimized app process, and the exact product sandbox. The host was Mac16,8 (arm64, 24 GiB), macOS 26.6.2 (25G83), Xcode 26.6 (17F113), on AC power, with nominal initial thermal state and warm filesystem caches after fixture preparation. No personal files were opened. The local filesystem retained about 49 GiB free; no runner-cache or user-data cleanup was performed.

The environment recorder does not independently verify keyboard/mouse exclusivity. Since the idle collection lost foreground status before completing, no accepted retry is included here. The next physical run needs a fresh confirmed exclusive-input interval and an explanation or correction for the Instruments attach failure before repeating that profile. The prior timeout and partial measurement remain preserved; no result was silently discarded or relabeled.
