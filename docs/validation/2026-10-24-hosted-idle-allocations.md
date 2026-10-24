# Hosted idle Allocations capture

Run: [GitHub Actions 40080144124](https://github.com/Orbitane-Limited/NoteHush/actions/runs/40080144124)  
Source: `35257a8219d3244bdcf46560ab48f06a082612ee`  
Artifact: `hosted-idle-allocations-35257a8219d3244bdcf46560ab48f06a082612ee-1` (ID `12555215457`, three-day retention)

The dedicated GitHub-hosted macOS 26 workflow completed successfully. The harness built and verified the isolated ReleasePerformance app, captured separate 60-second Allocations traces for generated empty and 20-tab/five-MiB workspaces, normally terminated each process, and verified each fixture's recovery and presentation state. The artifact contains both raw `.trace` bundles, fixture and environment manifests, collection log, and Instruments table-of-contents XML. The raw bundles were about 16 MiB and 20 MiB.

The runner reported a virtual ARM64 Mac (`VirtualMac2,1`), 7 GiB memory, three logical CPUs, macOS 26.6.2, and Xcode 26.6. The recorded app binary SHA-256 is `5b32de5af2a5fd56eee758f18c2759b9fa0d3e742b034d4433c2045959646556`. The fixture manifest contains generated data only.

The `--toc` export is an index; the Statistics and Allocations List values require selecting the named detail under the Allocations track. The exported end-of-recording heap data reports:

| Generated workspace | Live allocation rows | Live heap bytes |
| --- | ---: | ---: |
| Empty | 55,829 | 8,805,392 (8.40 MiB) |
| 20 tabs, five-MiB fixture | 100,493 | 25,753,984 (24.56 MiB) |

The five-MiB fixture run had 16,948,592 more live heap bytes than the empty run. This is one comparison on a hosted virtual machine; Allocations heap bytes are not process RSS or physical footprint. These values are diagnostic only and do not measure the PRD's empty-workspace RSS target.

Allocation rows do not provide useful source attribution in these traces: `responsible-caller` is `<Call stack limit reached>` for 99.92% of the empty run's live bytes and 99.24% of the five-MiB run's live bytes; those rows also have no responsible library. This identifies a capture limitation, not the owner of the allocations or a source-level fix. The `xctrace export` Allocations detail selector is supported by the [Xcode 13 release notes](https://developer.apple.com/documentation/Xcode-Release-Notes/xcode-13-release-notes). A follow-up capture now launches only the generated fixture app with `MallocStackLogging=lite`, as [Apple documents for allocation stack capture](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/ManagingMemory/Articles/MallocDebug.html). That diagnostic setting adds overhead; its trace can help attribute allocations but cannot establish the uninstrumented RSS target. Results from the follow-up capture are not available yet.

The capture script's fixture checks passed, but the environment manifest explicitly records that exclusive GUI input was not automatically verified. This is hosted diagnostic evidence only. The physical Mac before/after idle RSS, CPU, recovery and reference-hardware target measurements remain outstanding, and the relevant native UI automation preflight still reports Automation Mode disabled.

## Follow-up with malloc stack logging

Run: [GitHub Actions 40081911639](https://github.com/Orbitane-Limited/NoteHush/actions/runs/40081911639)

Artifact: `hosted-idle-allocations-d112f88ac7c2825368b4f378e9c4ebb78f6b65de-1` (ID `12555193938`)

The isolated performance app built and passed fixture preparation. Instruments recorded the full 60-second window for the generated empty workspace, but did not finish flushing before the 90-second recorder-process bound. The workflow retained the failed artifact, including an incomplete trace whose `event_data_5927.oa` is 102,764,544 bytes. This is not a completed Allocations result; no stack-attribution conclusion is drawn from it, and the 20-tab fixture was not reached. The next attempt keeps the 60-second sample and allows xctrace up to 180 seconds total, leaving up to 120 seconds after the sample to flush the larger stack-enabled trace.
