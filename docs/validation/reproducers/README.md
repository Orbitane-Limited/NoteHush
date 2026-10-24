# Native long-paragraph reproducer

The first executions of the prepared [font-policy and fragment-range controls](../2026-10-22-long-paragraph-controls.md) are now recorded. Their exact sources are [CoreTextFontPolicyProbe.swift](CoreTextFontPolicyProbe.swift) and [TextKitFragmentRangeProbe.swift](TextKitFragmentRangeProbe.swift); original drivers are [run-coretext-font-policy-probe.py](run-coretext-font-policy-probe.py) and [run-textkit-fragment-range-probe.py](run-textkit-fragment-range-probe.py). Copy each source and its driver together into a new private directory under `build` before invoking that driver. It retains a fresh UUID artifact directory beside the copied files. Run only after other native work finishes and the unchanged capacity checks pass. The drivers record every fixed matrix cell; their own successful exit does not imply those cells passed. Read each cell's timeout/exit/coverage result. These matrices are diagnostics, not release tests, and none established a product correction.

[`CoreTextLongProbe.swift`](CoreTextLongProbe.swift) is an exact copy of the previously compiled, isolated source behind the [issue #75 investigation](../2026-09-09-long-paragraph-investigation.md). SHA-256: `f95846721e71de03eb173e85ff458e835c2b4282f3212a1a88e3b35d8fb45cb8`.

It constructs generated Arabic/emoji text in memory and calls public Core Text APIs. It opens no window, reads no document, sends no input, uses no accessibility API and changes no system setting. Its output contains only the declared case and numeric observations. It is a diagnosis, not an editor or a release performance test.

The original matrix used 262,144 and 1,048,576 UTF-8 bytes, one fresh process for each of five variants, and a fixed ten-second process bound. `native`, `rtl`, `noLigatures` and `forcedRTL` all timed out at both sizes. `bounded` returned a null typesetter. A null result does not establish successful text layout. Earlier results and every failure remain in the investigation's evidence index.

To repeat a single declared case on an awake development Mac with Xcode installed, run:

```sh
python3 docs/validation/reproducers/run_coretext_probe.py 262144 native
```

The host script checks the repository's unchanged disk reserve and native process names before compiling and again before running the case. It compiles into a new private UUID directory under `build/logs`, sanitizes the child environment and runs the generated process once, for at most ten seconds. It keeps source, compiler output, case output and a numeric result. A failed or timed-out case exits unsuccessfully; it never retries or converts that outcome into a passing sample. The selected case is an additional diagnosis, not a continuation of the original matrix. Compiler availability, storage and other preparation failures are distinct from an executed native case. The preflight samples do not continuously monitor unrelated work throughout execution.

`firstLineAvailable` or complete editor rendering is not an output of this reproducer. Its positive result establishes only Core Text typesetter creation. Any editor correction still needs full glyph coverage, native Unicode/selection/undo/viewport behavior, exact recovery, resource bounds and the original application protocols.

An [unsubmitted Apple feedback draft](APPLE_FEEDBACK_DRAFT.md) collects the minimal steps, exact observed environment, relevant hot path and the limits of the evidence. It has not been sent to Apple or another party.

The separately compiled [font/run-range matrix source](CoreTextFallbackProbe.swift) is also retained exactly (SHA-256 `de681a054a12c884bc5a7652373cd0b9b3959d3e551610302d1aecb4d43eeba5`). It generated the twelve recorded 16 KiB/256 KiB/1 MiB cases and verifies only the first line. It has no explicit paragraph-style attribute, unlike the minimal source above. Its original driver and all outcomes remain in the investigation's private artifact index. The single-case host command above runs `CoreTextLongProbe.swift`; it does not run this second matrix.

The [virtual paragraph viewport probe](VirtualParagraphViewportProbe.swift) and [driver](run-virtual-paragraph-viewport-probe.py) compile an optimized, headless TextKit 2 process and generate a 10 MiB fixture in memory. The initial viewport matrix used four chunk sizes and four requested ranges; its results are in [the viewport report](../2026-10-23-virtual-paragraph-viewport.md). The current driver adds a 16-cell control matrix for `limitsLayoutForSuspiciousContents` (on/off), unchunked or 4,032-unit elements, and full or three viewport requests. Its results are in [the defensive-layout report](../2026-10-23-suspicious-layout-limit.md). The driver runs one fresh process per cell with a ten-second bound and retains source, binary, compiler output, JSONL observations, plan and results under a new private `build/` directory. Run it from a checkout with Xcode 26.6 using:

```sh
python3 docs/validation/reproducers/run-virtual-paragraph-viewport-probe.py
```

The current matrix probes only this generated fixture and these fixed modes. A completed viewport cell verifies its exact generated byte size and requested line coverage; full-layout cells report whether the process completed and whether complete text coverage was returned. The matrix is not an editor test or a performance acceptance run; it does not verify arbitrary bidi semantics, text input, undo, accessibility or recovery.

[`LegacyWrapModeProbe.swift`](LegacyWrapModeProbe.swift) compares TextKit 1 word wrapping with character wrapping on the exact generated mixed-script paragraph at 1 MiB and 10 MiB. Its driver compiles once, runs each cell in a fresh process with a ten-second bound and retains compiler/process output privately under `build/`. See the [recorded matrix](../2026-10-23-legacy-wrap-mode.md); timeouts are failures, not successful layout.

The current shipping candidate can be rechecked with the generated app-level long-paragraph protocol. It opens one exact-size Arabic/emoji paragraph in a fresh performance app process, allows ten seconds for the durable checkpoint, verifies recovered text, file binding, selection, viewport and source bytes if the checkpoint completes, then performs normal Quit. A timeout is recorded with elapsed duration, and the generated input, partial observations and failure logs remain under a private `build/logs/LargeOpen-<UUID>` directory. It never uses a user document or sends keyboard input. Run only with an isolated desktop and exclusive GUI input:

```sh
NOTEHUSH_EXCLUSIVE_INPUT=1 python3 scripts/test_long_paragraph.py --bytes 10485760
```

The size can be reduced to any byte count divisible by eight, up to 10 MiB. This protocol rechecks current app behavior; it is not a passing performance test or a correction for #75. Do not pool its single observation with the established 20-sample opening suite.

On a long-paragraph timeout, the harness samples only the exact owned app PID for two seconds **after** the ten-second observation ends. It retains the raw sample alongside the failure, and logs its status and SHA-256. The sample does not extend or change the checkpoint deadline. The [current hosted report](../2026-10-24-current-long-paragraph-controls.md) records the first timeout and the follow-up profile of the same unchanged app binary.

[`TextKitBaseDirectionProbe.swift`](TextKitBaseDirectionProbe.swift) is the exact generated, headless TextKit 2 control comparing natural and explicit RTL paragraph base directions. Its first 16 KiB geometry result and both 10 MiB timeout outcomes are recorded in the [current candidate controls report](../2026-10-24-current-long-paragraph-controls.md). [`CFWritingDirectionProbe.swift`](CFWritingDirectionProbe.swift) is the separate Core Foundation direction-classifier call used by the same report. These controls are diagnostics; neither is an app acceptance test.

[`NSTextViewDelegateEarlyProbe.swift`](NSTextViewDelegateEarlyProbe.swift), [`NSTextViewCustomStorageInitializationProbe.swift`](NSTextViewCustomStorageInitializationProbe.swift), and [`NSTextViewWithCustomManagerProbe.swift`](NSTextViewWithCustomManagerProbe.swift) are generated-data attempts to render 10 MiB chunked paragraph elements inside the framework `NSTextView`. The current run outcomes, source hashes, and binary hashes are in the [current candidate report](../2026-10-24-current-long-paragraph-controls.md). The probes produce incomplete layout or a native exception; they are not app tests or successful integration patterns.
