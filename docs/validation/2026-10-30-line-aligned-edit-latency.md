# Line-aligned TextKit edit latency investigation

Issue #75 remains unresolved. These generated-data probes test whether grouping
Core Text-planned native line spans into elements of at most 512 UTF-16 units
can make an editable `NSTextView` responsive on a long paragraph. They do not
change app behavior and read no user files.

## Findings

The 512-unit grouped plan preserved exact native line ranges and measured
typographic widths after insertion and undo on three generated 120–124 KiB
Unicode controls (RTL with emoji, mixed Latin/Urdu/Hebrew/punctuation/emoji,
and combining marks with Arabic/Hebrew/emoji). The 10 MiB Arabic/emoji control
planned 56,989 native line spans in 1.328 seconds. One midpoint insertion took
16.16 ms including replanning and native range layout; text, caret, undo and
visible target coverage were exact. This is one sample, not a latency
distribution, and it misses the one-second opening target.

The repeated-input probe then inserted 20 characters at that midpoint and
checked an immutable UTF-16 baseline. Text and undo were exact, but incremental
reflow alternated between one 2,048-unit window and a full 1,296-window suffix
replan. The measured median input-to-reflow/layout time was 29.46 ms and p95
was **7,510 ms**. This fails the interaction target and rejects this approach
as an app fix. Its initial plan took 3.391 seconds on this run.

The separate fixed-size `IncrementalChunkEditProbe` remains unsuitable: its
4,048-unit element had 29.43 ms median and 30.01 ms p95 in synchronous
`ensureLayout`. Reducing fixed elements to 512 units failed its viewport
coverage assertion. Therefore the promising small-control geometry and single
edit sample do not establish a usable editor design.

No app source was changed. Keep #75 open. A candidate still needs bounded
repeated typing latency, exact native geometry and selection behavior across
Unicode, IME, undo/redo, viewport coverage and scrolling, recovery, and full app
integration before it can be considered.

## Reproduction

Compile and run the `CoreTextLargeNSTextView512MiddleTypingProbe.swift` source
with Swift 6 and the macOS 14 SDK. It generates the 10 MiB paragraph in
memory. `CoreTextIncrementalNSTextView512Probe.swift` contains the three small
geometry controls; `CoreTextLargeNSTextView512Probe.swift` contains the single
edit control. The latency probes are independent diagnostic sources and do not
form part of the release test suite.
