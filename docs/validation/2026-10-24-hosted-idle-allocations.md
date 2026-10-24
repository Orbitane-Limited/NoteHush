# Hosted idle Allocations capture

Run: [GitHub Actions 40080144124](https://github.com/Orbitane-Limited/NoteHush/actions/runs/40080144124)  
Source: `35257a8219d3244bdcf46560ab48f06a082612ee`  
Artifact: `hosted-idle-allocations-35257a8219d3244bdcf46560ab48f06a082612ee-1` (ID `12555215457`, three-day retention)

The dedicated GitHub-hosted macOS 26 workflow completed successfully. The harness built and verified the isolated ReleasePerformance app, captured separate 60-second Allocations traces for generated empty and 20-tab/five-MiB workspaces, normally terminated each process, and verified each fixture's recovery and presentation state. The artifact contains both raw `.trace` bundles, fixture and environment manifests, collection log, and Instruments table-of-contents XML. The raw bundles were about 16 MiB and 20 MiB.

The runner reported a virtual ARM64 Mac (`VirtualMac2,1`), 7 GiB memory, three logical CPUs, macOS 26.6.2, and Xcode 26.6. The recorded app binary SHA-256 is `5b32de5af2a5fd56eee758f18c2759b9fa0d3e742b034d4433c2045959646556`. The fixture manifest contains generated data only.

The exported XML confirms that each trace has an Allocations track with Statistics and Allocations List details, plus a VM Tracker Regions Map detail. The `--toc` export is an index, not the allocation measurements. A generic table export did not expose allocation rows as a named data table, so this run does not establish allocation totals or identify a source-level memory fix. Keep the raw trace bundles available for Instruments review; do not infer the empty-workspace RSS budget from this hosted virtual machine.

The capture script's fixture checks passed, but the environment manifest explicitly records that exclusive GUI input was not automatically verified. This is hosted diagnostic evidence only. The physical Mac before/after idle RSS, CPU, recovery and reference-hardware target measurements remain outstanding, and the relevant native UI automation preflight still reports Automation Mode disabled.
