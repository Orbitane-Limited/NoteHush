# Native TextKit soft-break delegate control

Issue #75 remains unresolved. This generated-data probe tests whether `NSTextLayoutManagerDelegate` can force presentation-only line breaks at fixed UTF-16 offsets before native shaping blocks. It uses the ordinary TextKit 2 `NSTextView` and leaves the source string unchanged.

The delegate implements `textLayoutManager(_:shouldBreakLineBefore:hyphenating:)`. On an exact 16,384-byte control, it received 4,843 callbacks, forced 126 breaks at a 128-unit stride, completed viewport layout in 44.9 ms initially and 46.4 ms when repeated from the formatted committed source. Both runs preserved the exact string and 8,200 UTF-16 units. This is a single control observation; the forced breaks alter line geometry and do not establish equivalence with native wrapping.

On the exact generated 10,485,760-byte Arabic/emoji paragraph from #75, assigning the source completed and reported the expected byte count. A fresh process then exceeded the unchanged 12-second bound while ensuring the 858-by-600 viewport. An immediate flushed marker in the delegate’s first callback was never written, so TextKit did not reach the soft-break hook during that interval. The hook therefore cannot interrupt the measured pre-layout stall in this integration.

The reproduction source is [`NativeSoftBreakDelegateProbe.swift`](reproducers/NativeSoftBreakDelegateProbe.swift), SHA-256 `09051a32da0387dbddabfe2cd095a87b6f8c8b3d0c8fdbcf05ed967f62a11bf6`. It prints only generated fixture size/digest, UTF-16 length, timing, callback counts and whether the original string stayed exact. No app code, file limits, paragraph contents, assertions or timeout values changed. The delegate approach is not a product correction; do not add it to the editor based on the small control.

The public hook is documented by Apple in [`NSTextLayoutManagerDelegate`](https://developer.apple.com/documentation/appkit/nstextlayoutmanagerdelegate).
