# Hosted idle Allocations capture

Run: [GitHub Actions 40080144124](https://github.com/Orbitane-Limited/NoteHush/actions/runs/40080144124)  
Source: `35257a8219d3244bdcf46560ab48f06a082612ee`  
Artifact: `hosted-idle-allocations-35257a8219d3244bdcf46560ab48f06a082612ee-1` (ID `12555215457`, three-day retention)

The dedicated GitHub-hosted macOS 26 workflow completed successfully. The harness built and verified the isolated ReleasePerformance app, captured separate 60-second Allocations traces for generated empty and 20-tab/five-MiB workspaces, normally terminated each process, and verified each fixture's recovery and presentation state. The artifact contains both raw `.trace` bundles, fixture and environment manifests, collection log, and Instruments table-of-contents XML. The raw bundles were about 16 MiB and 20 MiB. The statistics below were later exported from those retained traces using the Allocations detail selectors.

The runner reported a virtual ARM64 Mac (`VirtualMac2,1`), 7 GiB memory, three logical CPUs, macOS 26.6.2, and Xcode 26.6. The recorded app binary SHA-256 is `5b32de5af2a5fd56eee758f18c2759b9fa0d3e742b034d4433c2045959646556`. The fixture manifest contains generated data only.

The `--toc` export is an index; the Statistics and Allocations List values require selecting the named detail under the Allocations track. The exported end-of-recording heap data reports:

| Generated workspace | Live allocation rows | All Heap & Anonymous VM bytes |
| --- | ---: | ---: |
| Empty | 55,829 | 8,805,392 (8.40 MiB) |
| 20 tabs, five-MiB fixture | 100,493 | 25,753,984 (24.56 MiB) |

The five-MiB fixture run had 16,948,592 more live All Heap & Anonymous VM bytes than the empty run. This is one comparison on a hosted virtual machine; Allocations bytes are not process RSS or physical footprint. These values are diagnostic only and do not measure the PRD's empty-workspace RSS target.

Allocation rows do not provide useful source attribution in the baseline traces: `responsible-caller` is `<Call stack limit reached>` for 99.92% of the empty run's live bytes and 99.24% of the five-MiB run's live bytes; those rows also have no responsible library. This identifies a capture limitation, not the owner of the allocations or a source-level fix. The `xctrace export` Allocations detail selector is supported by the [Xcode 13 release notes](https://developer.apple.com/documentation/Xcode-Release-Notes/xcode-13-release-notes). The following sections document the stack-logging follow-up and what it did and did not establish.

The capture script's fixture checks passed, but the environment manifest explicitly records that exclusive GUI input was not automatically verified. This is hosted diagnostic evidence only. The physical Mac before/after idle RSS, CPU, recovery and reference-hardware target measurements remain outstanding, and the relevant native UI automation preflight still reports Automation Mode disabled.

## Follow-up with malloc stack logging

Run: [GitHub Actions 40081911639](https://github.com/Orbitane-Limited/NoteHush/actions/runs/40081911639)

Artifact: `hosted-idle-allocations-d112f88ac7c2825368b4f378e9c4ebb78f6b65de-1` (ID `12555193938`)

The isolated performance app built and passed fixture preparation. Instruments recorded the full 60-second window for the generated empty workspace, but did not finish flushing before the 90-second recorder-process bound. The artifact records source `d112f88ac7c2825368b4f378e9c4ebb78f6b65de`, binary SHA-256 `5b32de5af2a5fd56eee758f18c2759b9fa0d3e742b034d4433c2045959646556`, and the incomplete `event_data_5927.oa` (102,764,544 bytes, SHA-256 `7fd5bdc0ce9feb4f72bbf46be5c53acbdaf7064c3956594bc59fd4c89016dbc4`). This is not a completed Allocations result; no stack-attribution conclusion is drawn from it, and the 20-tab fixture was not reached. The subsequent run kept the 60-second sample and increased the xctrace process bound to 180 seconds, leaving up to 120 seconds after the sample to flush.

## Completed stack-enabled capture

Run: [GitHub Actions 40082553474](https://github.com/Orbitane-Limited/NoteHush/actions/runs/40082553474)
Artifact: [hosted-idle-allocations-a5c265a004a1b4ddcba7ba9e9555ad999ebba4a0-1](https://github.com/Orbitane-Limited/NoteHush/actions/runs/40082553474/artifacts/12555238450) (ID `12555238450`)

The isolated app completed both 60-second traces, the three Xcode exports per trace (table of contents, Allocations Statistics, Allocations List), normal termination, and exact recovery/presentation checks. The source was `a5c265a004a1b4ddcba7ba9e9555ad999ebba4a0`; the binary SHA-256 was unchanged. The runner was again a virtual ARM64 Mac with macOS 26.6.2 and Xcode 26.6. `MallocStackLogging=lite` was enabled for these diagnostic app processes.

| Generated workspace | Live allocation rows | All Heap & Anonymous VM | All Heap Allocations |
| --- | ---: | ---: | ---: |
| Empty | 51,784 | 255,429,344 bytes (243.60 MiB) | 9,554,656 bytes (9.11 MiB) |
| 20 tabs, five-MiB fixture | 94,759 | 501,042,592 bytes (477.83 MiB) | 28,052,896 bytes (26.75 MiB) |

These totals are from stack-logging traces and are not product memory measurements. They are far above the earlier uninstrumented trace's combined heap/anonymous-VM values, so this mode must not be used to assess RSS or physical-footprint acceptance. The rows do expose responsible-caller/library labels. Largest live VM allocation groups included `BOMStorageOpenWithSys` in CoreUI (190,904,064 bytes in both workspaces), `TFileDataReference::Map(char const*)` in libFontParser (203,341,824 bytes in the five-MiB fixture), and Foundation localization data. The five-MiB trace also includes 7,270,400 bytes attributed to `copyFromStringToStorage`. These labels point to system allocation sites, but the Xcode 26.6 XML exports contain no backtrace frame rows. They therefore do not establish a complete caller chain or justify a NoteHush source change. Direct NoteHushPerformance `responsible-library` rows account for 44,352 / 133,488 bytes in the empty / five-MiB trace; this is direct-caller attribution only, not total memory owned by the app.

The hosted capture, its virtual memory totals, and the earlier uninstrumented Allocations totals do not substitute for the unchanged physical Mac before/after RSS, CPU, recovery and reference-hardware protocol. No production memory change is established by these captures.

## Bounded malloc-history attribution

Run: [GitHub Actions 40096941353](https://github.com/Orbitane-Limited/NoteHush/actions/runs/40096941353). Source: `e8f7a3ac537ac7783e5be842f4ce83bde26448e4`. Artifact: `hosted-idle-allocations-e8f7a3ac537ac7783e5be842f4ce83bde26448e4-1`.

The harness queried bounded `malloc_history` backtraces for up to eight largest live allocations directly attributed to the isolated `NoteHushPerformance` process in each generated workspace. The hosted run completed successfully and retained full symbolicated stacks, including NoteHush frames and source locations. This works on the hosted runner, where the harness can use non-interactive administrator authorization for its own generated fixture process; the local machine's sandboxed `malloc_history` probe could not inspect a process.

Both fixtures showed the same sampled NoteHush-owned allocation groups: a 20,480-byte allocation from `TabBarView.reveal(_:)` during selected-tab presentation, a 2,560-byte allocation from the performance app's `sendEvent(_:)`, and smaller AppKit objects created by `TabBarView` and `EditorTab` (including the tab-bar and editor scroll views, text view, stack view, button and box). The same top sampled groups in both fixtures do not establish that the five-MiB text buffer is free of additional allocations: only the eight largest direct NoteHush-attributed live addresses per fixture were queried, and allocations attributed to system libraries are outside that selection.

This attribution does not show a large NoteHush allocation suitable for an evidence-backed source change, nor does it establish ownership of total process memory. The capture remains diagnostic and instrumented. Physical Mac RSS, CPU, recovery and reference-hardware measurements are still required for the product memory targets; no production memory change or memory-budget acceptance is established.
