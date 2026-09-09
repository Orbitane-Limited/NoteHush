# Native long-paragraph reproducer

[`CoreTextLongProbe.swift`](CoreTextLongProbe.swift) is an exact copy of the previously compiled, isolated source behind the [issue #75 investigation](../2026-09-09-long-paragraph-investigation.md). SHA-256: `f95846721e71de03eb173e85ff458e835c2b4282f3212a1a88e3b35d8fb45cb8`.

It constructs generated Arabic/emoji text in memory and calls public Core Text APIs. It opens no window, reads no document, sends no input, uses no accessibility API and changes no system setting. Its output contains only the declared case and numeric observations. It is a diagnosis, not an editor or a release performance test.

The original matrix used 262,144 and 1,048,576 UTF-8 bytes, one fresh process for each of five variants, and a fixed ten-second process bound. `native`, `rtl`, `noLigatures` and `forcedRTL` all timed out at both sizes. `bounded` returned a null typesetter. A null result does not establish successful text layout. Earlier results and every failure remain in the investigation's evidence index.

To repeat a single declared case on an awake development Mac with Xcode installed, run:

```sh
python3 docs/validation/reproducers/run_coretext_probe.py 262144 native
```

The host script checks the repository's unchanged disk reserve and native process names before compiling and again before running the case. It compiles into a new private UUID directory under `build/logs`, sanitizes the child environment and runs the generated process once, for at most ten seconds. It keeps source, compiler output, case output and a numeric result. A failed or timed-out case exits unsuccessfully; it never retries or converts that outcome into a passing sample. The selected case is an additional diagnosis, not a continuation of the original matrix. Compiler availability, storage and other preparation failures are distinct from an executed native case. The preflight samples do not continuously monitor unrelated work throughout execution.

`firstLineAvailable` or complete editor rendering is not an output of this reproducer. Its positive result establishes only Core Text typesetter creation. Any editor correction still needs full glyph coverage, native Unicode/selection/undo/viewport behavior, exact recovery, resource bounds and the original application protocols.
