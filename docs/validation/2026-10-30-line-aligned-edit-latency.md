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

Reducing the incremental reflow window from 2,048 to 512 UTF-16 units also did
not bound the worst case. It converged after roughly 20 units for many
insertions, but alternating insertions still reflowed the suffix through the
document end in 5,699 windows; the 20-edit p95 was 7,644 ms. Exact text and
undo still passed. This rules out window size alone as a correction.

A follow-up placed the 512-group custom-content `NSTextView` inside a real
`NSScrollView` and attempted `scrollRangeToVisible` at the midpoint. AppKit
threw an uncaught `NSInvalidArgumentException` while attaching the document
view, before the scroll call: `NSCountableTextLocation compare: receiving
unmatching type (null)`. The stack enters
`estimatedSizeForLastTextContainer` and `NSTextView.sizeToFit` during
`NSScrollView.setDocumentView`. Targeted-range coverage in the prior probe did
not establish scroll-view integration; this attempt failed that requirement.

A second integration control used native superclass locations from
`NSTextContentStorage`, 512-unit planner chunks, and a real scroll view. The
editor attached and laid out its first 4,716 UTF-16 units in 6.87 ms. Planning
the generated document through its midpoint took 2,666 ms across 5,587 chunks,
and a direct `ensureLayout` for the target range returned. Calling the native
`scrollRangeToVisible` then threw the same location-comparison exception from
`NSTextView._boundingRectForTextRange`. So native locations improved the
initial attachment and first viewport, but did not make actual midpoint
scrolling work; planning to the midpoint also exceeded the one-second target.

Replacing `scrollRangeToVisible` with a direct clip-view scroll avoids that
exception but also fails to move the viewport. The target fragment reports
`frameY=0.0`, the `NSTextView` remains 500 points tall, and the clip-view origin
stays at zero. Thus targeted range layout has no document-space position for
the middle fragment in this setup. The retained
`NativeProgressive512ManualScrollProbe.swift` records this control; source
SHA-256: `873f831aa5235f3ea28b26703cf147f417949652f6e91671be6606af031023c5`.

No app source was changed. Keep #75 open. A candidate still needs bounded
repeated typing latency, exact native geometry and selection behavior across
Unicode, IME, undo/redo, viewport coverage and scrolling, recovery, and full app
integration before it can be considered.

## Reproduction

Compile and run the `CoreTextLargeNSTextView512MiddleTypingProbe.swift` source
with Swift 6 and the macOS 14 SDK. It generates the 10 MiB paragraph in
memory. `CoreTextIncrementalNSTextView512Probe.swift` contains the three small
geometry controls; `CoreTextLargeNSTextView512Probe.swift` contains the single
edit control. `CoreTextLargeNSTextView512Window512TypingProbe.swift` repeats
the 20-edit probe with 512-unit reflow windows.
`CoreTextLargeNSTextView512ScrollProbe.swift` attempts actual `NSScrollView`
attachment and midpoint scrolling. The probes are independent diagnostics and
`NativeProgressive512ViewportProbe.swift` combines native superclass
locations with 512-unit chunks and a midpoint scroll request. These probes
are diagnostics and are not part of the release test suite. The native-location
source SHA-256 is
`7192158a3b1bdee12d22eec870f3f6a0aa39b7b1b7f29d0cdafc1fc59e9f59c2`.

## Exact repeated-input observations

The 2,048-unit run produced:

```text
sourceBytes=10485760 planSeconds=3.391093208 seconds
typing20MedianMs=29.459166 typing20P95Ms=7510.384792
reflowMedianMs=12.0025 ensureMedianMs=1.951292
reflowWindows=[1,1296,1,1296,1,1296,1,1296,1,1296,1,1,1296,1,1296,1,1296,1,1296,1]
textMismatch=false exactText=true caret=2621464 chunkCount=23 attached=true
undoCount=1 undoExact=true undoCaret=true
```

The 512-unit reflow-window run produced:

```text
sourceBytes=10485760 planSeconds=1.371452375 seconds
typing20MedianMs=22.8981875 typing20P95Ms=7643.9995
reflowMedianMs=6.95725 ensureMedianMs=1.886208
reflowWindows=[1,5699,1,5699,1,5699,1,5699,1,5699,1,1,5699,1,5699,1,5699,1,5699,1]
textMismatch=false exactText=true caret=2621464 chunkCount=23 attached=true
undoCount=1 undoExact=true undoCaret=true
```

The UTF-16 source snapshot is copied before editing. The earlier mutable
Foundation bridge baseline produced a false mismatch and is not used for these
results. Source SHA-256 values: `CoreTextLargeNSTextView512MiddleTypingProbe.swift`
`166735ad11f929b8670562c2ab9d02de5211645a9035a6eac4e189dbabdf2220`,
`CoreTextLargeNSTextView512Window512TypingProbe.swift`
`2bc702724933bbd9b2ff038e295d49b88d4a799deafc434e024377933ec2871c`, and
`CoreTextLargeNSTextView512ScrollProbe.swift`
`f4e11eb243a5783a6993a14ae904aa22a59b7f45a4ce7cd972d04c3210c11253`.
