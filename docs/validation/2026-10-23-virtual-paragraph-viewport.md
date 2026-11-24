# Virtual paragraph viewport experiment

Issue #75 remains open. This follow-up asks whether a custom TextKit 2 provider can lay out only a requested text range in the exact generated 10 MiB fixture without laying out the complete document. It runs headlessly with generated data and does not modify the app.

## Protocol and result

The fixture is exactly 10,485,760 UTF-8 bytes: the same 16-byte header followed by repetitions of `"خط📝"`. A custom `NSTextContentManager` exposes separate `NSTextParagraph` elements. Four chunk lengths (384, 768, 1,536 and 4,032 UTF-16 units) are multiples of the 96-unit line length observed for this exact 14-point monospaced fixture at 900 points. Each fresh process requests and lays out one range: the header, the first text, the middle, or the end. The oracle requires exact source byte size and contiguous laid-out line coverage of the requested range.

All 16 cells exited successfully, preserved the exact source size, covered the requested line range and produced matching target geometry digests across all four chunk sizes for each requested location. Observed single-cell ranges across the chunk sizes were:

| Requested range | Observed elapsed range | Laid-out lines |
| --- | ---: | ---: |
| Header | 0.036–1.013 s | 1 |
| First text | 0.038–0.064 s | 11 |
| Middle | 0.039–0.064 s | 12 |
| End | 0.036–0.038 s | 3 |

There is one observation per cell; these numbers are diagnostic timings, not p95 performance results. Matching geometry is only between chunk sizes for the selected ranges. It does not compare full 10 MiB native layout, prove arbitrary-text equivalence, or show that the application can edit this content model.

## Integration limit

Apple documents `NSTextView` as using `NSTextContentStorage` for its text backing store, while a custom `NSTextContentManager` is intended for a custom `NSView` text display ([TextKit](https://developer.apple.com/documentation/appkit/textkit)). A headless attempt to replace the standard text view's manager with the prototype did not produce an editable view: the standard view expected a text-storage-backed manager, and the incomplete `NSTextContentStorage` subclass failed its native location mapping with `NSInvalidArgumentException` (`offsetFromLocation:toLocation:` received null locations). The exact source, binary and exception record remain in the private artifact directory. This is a failed prototype, not evidence that an independently implemented custom editor is impossible.

Making this path shippable would require replacing `NSTextView` with a custom view and preserving text input, IME composition, selection, undo, accessibility, viewport restoration and recovery. That scope carries a substantial regression risk and has not been implemented or tested. The chunk boundaries also rely on one font, width and repeated text pattern and may change paragraph direction/shaping semantics. The viewport result therefore remains a hypothesis, not an accepted correction.

## Evidence

The exact source and self-compiling driver are in [reproducers](reproducers/README.md). The [numeric matrix](2026-10-23-virtual-paragraph-viewport.json) records all 16 outcomes, requested ranges, geometry digests and source/binary SHA-256 values. Raw JSONL observations, compiler output and binaries remain in the private local artifact directory named in the matrix. No app acceptance, full-layout result, edit/IME behavior, resource bound, or release claim follows from this experiment.
