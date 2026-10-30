# TextKit writing-direction attribute control

Issue #75 remains unresolved. This generated-data control tests whether a presentation-only `NSAttributedString.Key.writingDirection` override avoids the 10 MiB mixed-paragraph stall while preserving the existing text. It uses standard `NSTextContentStorage`/`NSTextLayoutManager`, the app's 14-point monospaced font, 868-point container, natural paragraph style, and the issue's generated `خط📝` fixture. The stored string remains unchanged.

| Fixture | Attribute | Layout time | Lines / coverage | Geometry |
| --- | --- | ---: | --- | --- |
| 16 KiB | Natural | 68.462 ms | 90 / 8,200 UTF-16 | `345a42cbbe55877c43ba6e2656b238523a343c05c4ddec8fe4a3cdcd3aded3ad` |
| 16 KiB | RLE embedding | 69.396 ms | 90 / 8,200 UTF-16 | Same as natural |
| 16 KiB | LRE embedding | 75.557 ms | 90 / 8,200 UTF-16 | Same as natural |
| 10 MiB | RLE embedding | 20-second bound | No completed layout result | Timed out |

The explicit writing-direction attribute preserves the small fixture's native geometry, but does not make full TextKit layout of the unchanged 10 MiB source complete within 20 seconds. The timeout is a failed observation, not a latency sample. The value was applied only to an isolated attributed copy and never to application storage.

This rules out this single whole-range embedding override as the needed correction. It does not exhaust every possible run-level attribute strategy. No application code, file size limit, fixture, timeout in the app protocol, or acceptance criterion changed. The standalone source is [`TextKitWritingDirectionAttributeProbe.swift`](reproducers/TextKitWritingDirectionAttributeProbe.swift).

Source SHA-256: `5c1bb7e56ae06ad53911ccd811fec0c3c91545ec8e42806337165282694abf3e`.
Binary SHA-256: `b1b50505ab2950af1ef1f8e2048126b5761f115ec548e4628b62b342fd737577`.
