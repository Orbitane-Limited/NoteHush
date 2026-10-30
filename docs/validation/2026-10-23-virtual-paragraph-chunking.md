# Virtual paragraph chunking control

Issue #75 remains unresolved. This generated, headless AppKit experiment asks whether a custom public `NSTextContentManager` can expose bounded `NSTextParagraph` elements while preserving the UTF-16 document range. It does not change application source, create windows, or send input. The complete per-cell observations and binary/source are retained in the local private artifact directory recorded by `build/latest-virtual-paragraph-probe.json`.

## Setup

`NSTextContentStorageDelegate.textContentStorage(_:textParagraphWith:)` must return an attributed string with the requested range length, so that delegate cannot subdivide an existing paragraph. A custom content manager can enumerate custom elements, however; this prototype maps their element ranges into one contiguous global UTF-16 range. Each generated fixture is a 16-byte header plus exact repetitions of `"خط📝"`. The container width is 900 points, the font is 14-point monospaced system, and the paragraph base direction is natural. Each cell used a new process and a 10-second bound.

The result oracle requires the sum of all line-fragment UTF-16 lengths to equal the full document length, no out-of-range line fragments, and a stable digest over global UTF-16 start, line length and typographic width. The small fixture compares an unsplit native paragraph with line-aligned chunk sizes. Larger fixtures use the chunked provider only; this is not a cross-layout geometry comparison.

## Results

| Exact UTF-8 bytes | Chunk size (UTF-16) | Time | Result |
| ---: | ---: | ---: | --- |
| 16,384 | Native paragraph | 0.950 s | Complete; 8,200 UTF-16 units; 87 lines |
| 16,384 | 4,032 | 0.058 s | Complete; same geometry digest as native |
| 16,384 | 96 | 0.037 s | Complete; same geometry digest as native |
| 262,144 | 4,032 | 0.671 s | Complete; 131,080 UTF-16 units; 1,367 lines |
| 1,048,576 | 4,032 | 2.650 s | Complete; 524,296 UTF-16 units; 5,463 lines |
| 10,485,760 | 4,032 / 1,536 / 768 / 384 | 10-second bound | All four timed out |

The small fixture establishes that, for this exact repeated script, the selected element boundaries preserve its native line geometry. The 256 KiB and 1 MiB rows establish complete document coverage, not comparison with native geometry. No 10 MiB chunk size completed.

## Interpretation

This custom TextKit 2 content model is rejected as a correction for the current stall. It reproduces complete layout through 1 MiB but does not complete the unchanged 10 MiB mixed-script workload under the existing ten-second bound. It cannot satisfy #75 acceptance. It also does not test edits, IME, selection mapping after edits, undo, viewport behavior, recovery, memory, energy, or arbitrary mixed-direction paragraphs.

A separate Core Text diagnostic completed the same generated 10 MiB text in 7.396 seconds using 384 repeated text units per chunk, with exact contiguous coverage. That result remains a layout hypothesis: the app uses TextKit, and the TextKit custom-element implementation above did not complete the corresponding workload. The Core Text timing does not close the issue or show an integration path.

No file limit, content, paragraph structure, assertion, observation bound, or release target changed. Keep the issue open. Any future correction must complete the original application workload and preserve its editing, recovery and resource contracts before changing shipping code.

## Reproduction source

The exact generated probe and driver are checked in beside this report. Public API references: [NSTextContentManager](https://developer.apple.com/documentation/appkit/nstextcontentmanager), [NSTextElementProvider](https://developer.apple.com/documentation/appkit/nstextelementprovider), and [NSTextContentStorageDelegate](https://developer.apple.com/documentation/appkit/nstextcontentstoragedelegate).
