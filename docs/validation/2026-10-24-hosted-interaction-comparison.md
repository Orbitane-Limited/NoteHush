# Hosted interaction before/after comparison

This report records the unchanged `interaction` protocol for issue #45 on the same GitHub-hosted `macos-26` virtual M1 runner. Baseline and candidate were run sequentially in workflow [40040751540](https://github.com/Orbitane-Limited/NoteHush/actions/runs/40040751540). Both runs completed successfully, including the protocol's editing, undo, quit/restart and host recovery checks. Each revision produced 20 observations for each of four scenarios (160 observations per revision).

| Scenario | Interval | Baseline median / p95 (ms) | Candidate median / p95 (ms) |
| --- | --- | ---: | ---: |
| ASCII tab switch | Synchronous tab event dispatch | 48.729 / 74.105 | 12.801 / 20.695 |
| ASCII tab switch | XCTest monotonic round trip | 165.795 / 230.839 | 137.028 / 147.001 |
| Mixed-script tab switch | Synchronous tab event dispatch | 156.846 / 190.231 | 12.961 / 23.206 |
| Mixed-script tab switch | XCTest monotonic round trip | 233.965 / 265.605 | 116.235 / 144.840 |
| ASCII typing | Synchronous typing event dispatch | 2.005 / 2.849 | 2.662 / 4.694 |
| ASCII typing | XCTest monotonic round trip | 45.222 / 57.495 | 49.156 / 53.329 |
| Mixed-script typing | Synchronous typing event dispatch | 367.865 / 477.104 | 2.948 / 4.714 |
| Mixed-script typing | XCTest monotonic round trip | 436.283 / 555.192 | 53.953 / 58.483 |

The candidate lowers measured mixed-script event-dispatch median from 367.865 ms to 2.948 ms and p95 from 477.104 ms to 4.714 ms. ASCII typing dispatch rises by 0.657 ms at the median (2.005 → 2.662 ms) and 1.845 ms at p95 (2.849 → 4.694 ms), remaining in the low-millisecond range. The mixed-script tab-switch dispatch median falls from 156.846 ms to 12.961 ms. These results support a reduction in synchronous app work for these fixtures while preserving the measured ASCII cost as a small regression.

The XCTest clock interval also contains automation and event-delivery overhead. The dispatch signpost surrounds synchronous `sendEvent` processing only; neither interval measures physical input-to-visible latency or deferred display. Consequently, even values below the PRD's 16.7 ms typing and 50 ms switching targets do not establish those event-to-visible targets. These comparative results also do not meet the physical M1/8 GB acceptance gate.

## Reproduction and provenance

- Workflow: [40040751540](https://github.com/Orbitane-Limited/NoteHush/actions/runs/40040751540), successful baseline then candidate on one VM.
- Baseline source: `15fec0ed97a57f86a5f9331615213679da825d93`.
- Candidate source: `b52816792a3acd5e3aa6360ad26329e209bee126`.
- Both environments: `VirtualMac2,1`, arm64, 7 GiB RAM, 3 logical CPUs, macOS 26.6.2 (25G83), Xcode 26.6, Swift 6.3.3, ReleasePerformance optimized build, warm filesystem caches.
- The runner reports AC power, nominal initial thermal state, and one 1024×768-point display at scale 1. Input isolation was established for this comparison at the VM level: the workflow holds a single concurrency group and runs both revisions sequentially in one job on a newly provisioned GitHub-hosted VM; no other GUI job is assigned to that VM. GitHub documents that each standard hosted macOS job runs in a fresh VM ([runner documentation](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)). The harness's generic exclusivity field remains unverified because it cannot observe inputs outside the runner. This evidence does not establish exclusivity on the self-hosted physical Mac.
- The workflow artifact retained complete logs, raw observations, CSV metrics and result bundles for seven days. The compact summaries preserve every accepted sample and are committed here with each environment record.

Durable evidence files: [`baseline-summary.json`](2026-10-24-hosted-interaction/baseline-summary.json), [`candidate-summary.json`](2026-10-24-hosted-interaction/candidate-summary.json), and their adjacent environment JSON files. These measurements do not replace physical M1/M4 testing, minimum-OS and IME checks, memory/energy profiling, or the parent issue's other performance and release gates.
