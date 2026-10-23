# Core Text long-paragraph feedback draft

This is an unsubmitted technical draft for issue #75. No Feedback Assistant report or third-party message has been sent. All text is generated; the reproducer reads no user document and requires no UI automation permission.

**Proposed title:** Core Text typesetter creation does not return within ten seconds for a generated Arabic/emoji paragraph

**Observed environment:** Apple M4 Pro, 24 GiB, macOS 26.6.2 (25G83), Xcode 26.6 (17F113), Swift 6.3.3, native arm64. Other macOS versions and physical Intel hardware have not been checked for this reproduction.

## Minimal reproduction

Use the exact [Swift source](CoreTextLongProbe.swift), SHA-256 `f95846721e71de03eb173e85ff458e835c2b4282f3212a1a88e3b35d8fb45cb8`. It constructs an attributed string from repetitions of `خط📝`, sets the system monospaced font and a natural paragraph writing direction, then calls the public `CTTypesetterCreateWithAttributedStringAndOptions` API. The default diagnostic variant permits unbounded layout. There are no paragraph separators inside the generated text.

The committed [bounded host](run_coretext_probe.py) can run one declared case from the repository checkout:

```sh
python3 docs/validation/reproducers/run_coretext_probe.py 262144 native
```

It first checks capacity and competing native process names, compiles into a private UUID artifact directory with a sanitized environment, and runs the case once. The child has a ten-second process bound. It preserves every outcome and source/product hashes; it never retries the case. A preparation failure means the native case did not execute. This additional wrapper has host failure-injection coverage, but has not yet completed its own native invocation; the original results below used the separately retained original driver.

On 2026-10-23, the bounded command was attempted with `262144 native`. Both storage checks passed, but the managed shell denied its read-only `ps -axo comm=` preflight with `PermissionError`; `nativeCaseStarted` remained false, so no Core Text result was produced. The complete preparation result is retained locally at `build/logs/CoreTextReproducer-838C7FC3-1226-4706-A8ED-25AE87C86E17/result.json`. This environment restriction does not change the original native observations or establish a product outcome.

A second attempt on the same date ran the built-in preflight with process enumeration available. It found five competing native processes before compilation and stopped with `nativeCaseStarted: false`; no process names were retained and no Core Text case ran. Its result is local at `build/logs/CoreTextReproducer-436FD2B7-3EFA-4134-88BC-8385E754C98C/result.json`. The Mac was therefore not idle for this diagnostic at that time. This is another preparation outcome, not a new layout observation.

## Expected and observed results

Desired behavior is for supported text to become available to native layout without a long synchronous stall. Ten seconds is the diagnostic observation bound, not an asserted Apple API guarantee.

In the original fixed matrix, both 262,144-byte and 1,048,576-byte paragraphs timed out with the native/unbounded, explicit RTL, disabled optional ligatures and forced RTL embedding variants. Each cell was a fresh process and was terminated at its bound. No completion time beyond that bound is known. Disallowing unbounded layout returned a null typesetter in approximately 191 and 236 milliseconds; that is a declined layout, not complete text rendering.

A separate real-app reproduction opens a generated 10 MiB file consisting of a short header and one unbroken mixed paragraph. Both the retained TextKit 1 editor and the TextKit 2 candidate miss their ten-second checkpoint observation. A two-second sample attached only to the owned TextKit 2 process **after** the deadline found 1,451 of 1,453 main-thread samples at `TRunGlue::NextRunRange`, under `TShapingEngine::ShapeGlyphs`, typesetter creation and native text fragment layout. The sample identifies the observed hot path; it does not establish a particular internal defect or its algorithmic complexity. It is separate from unprofiled timing observations.

Assigning a public layout queue to native fragments permits the real app to checkpoint and quit normally, but separate completion observations still find the mixed paragraph in estimated layout state with eight pending operations after forty 200-millisecond main-actor ticks. Queuing therefore has not established completed glyph layout or cancellation of an active typesetter call.

## Evidence and limits

The [investigation](../2026-09-09-long-paragraph-investigation.md) and [artifact index](../2026-09-09-long-paragraph-investigation.json) retain the original matrices, complete outcomes, exact sources/binaries and app-only sample checksum. Raw sample, input fixtures, products and process results remain private in the referenced artifact directories. Only generated inputs and the relevant app-only evidence should be attached if a report is submitted; a whole-system diagnostic has not been collected.

The later font/run-range matrix is a separate experiment: it omits the explicit paragraph-style attribute used by the minimal reproducer. Its smaller native controls therefore cannot replace the original failures or establish an attributed-run workaround. No experiment here proves behavior on all supported systems, a completed editor fix, or App Store readiness.
