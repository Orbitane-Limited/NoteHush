# Hosted launch before/after comparison

This report records the unchanged `launch` protocol for issue #45, run baseline first and candidate second on the same GitHub-hosted `macos-26` virtual M1 runner. Workflow [40043148735](https://github.com/Orbitane-Limited/NoteHush/actions/runs/40043148735) completed successfully. Each of three workloads collected 20 observations for each of two intervals (120 accepted observations per revision). The protocol also verified editing, Undo, normal Quit, process termination and complete open/closed-buffer recovery.

| Workload | Interval | Baseline median / p95 (ms) | Candidate median / p95 (ms) |
| --- | --- | ---: | ---: |
| Empty workspace | First-frame `ApplicationLaunch` | 469.989 / 513.265 | 364.206 / 399.568 |
| Empty workspace | `ProcessToEditorReady` | 343.124 / 372.628 | 241.510 / 261.603 |
| 20 tabs, 5 MiB | First-frame `ApplicationLaunch` | 384.702 / 409.316 | 368.924 / 402.244 |
| 20 tabs, 5 MiB | `ProcessToEditorReady` | 1,251.462 / 1,318.657 | 429.400 / 453.621 |
| 100 open + 20 closed tabs, 30 MiB | First-frame `ApplicationLaunch` | 390.868 / 436.840 | 367.308 / 398.648 |
| 100 open + 20 closed tabs, 30 MiB | `ProcessToEditorReady` | 3,132.995 / 3,301.010 | 1,093.615 / 1,222.678 |

The candidate's `ProcessToEditorReady` p95 is 262 ms for an empty workspace and 454 ms for 20 tabs / 5 MiB. Those are below the corresponding 500 ms and 1 second targets on this hosted VM. The 30 MiB stress workload's readiness p95 is 1.223 seconds. These are virtual-M1 observations only; they do not establish the PRD targets on physical M1/8 GB hardware. `ApplicationLaunch` is the distinct first-frame interval and must not be described as editor-ready time. The readiness signpost ends after recovery, selected-editor installation, focus, layout and `displayIfNeeded`; it is not display scan-out latency.

## Reproduction and provenance

- Workflow: [40043148735](https://github.com/Orbitane-Limited/NoteHush/actions/runs/40043148735), successful baseline followed by candidate on one VM.
- Baseline source: `15fec0ed97a57f86a5f9331615213679da825d93`.
- Candidate source: `b52816792a3acd5e3aa6360ad26329e209bee126`.
- Both: `VirtualMac2,1`, arm64, 7 GiB RAM, 3 logical CPUs, macOS 26.6.2 (25G83), Xcode 26.6, Swift 6.3.3, optimized `ReleasePerformance` build, warm filesystem caches.
- One 1024×768-point display at scale 1, AC power, nominal initial thermal state. The harness records GUI-input exclusivity as unverified; only the single sequential job allocation is guaranteed here.
- The workflow artifact retains raw observations, CSVs, result bundles and full logs for seven days. The committed summaries preserve all 120 accepted samples per revision; the adjacent environment JSON files record exact source and binary provenance.

Durable evidence: [`baseline-summary.json`](2026-10-24-hosted-launch/baseline-summary.json), [`candidate-summary.json`](2026-10-24-hosted-launch/candidate-summary.json), and adjacent environment records. This does not replace physical M1/M4 measurements, macOS 14/Intel checks, memory/energy profiling, real IME/accessibility testing, or other parent-issue and App Store gates.
