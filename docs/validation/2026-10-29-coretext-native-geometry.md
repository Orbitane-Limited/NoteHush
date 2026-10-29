# Core Text versus native TextKit wrapping control

Issue #75 remains unresolved. This generated-data comparison checks whether a Core Text line index can provide exact native TextKit wrapping geometry for the custom range renderer. It uses one continuous paragraph per generated case, the app's 14-point monospaced font, natural paragraph direction, and an 858-point container. No application source or user document is involved.

## Results

| Generated case | UTF-8 bytes | UTF-16 units | TextKit lines | Core Text lines | Same line starts, lengths, and width digests |
| --- | ---: | ---: | ---: | ---: | --- |
| Repeated Arabic + emoji (`خط📝`) | 16,000 | 8,000 | 87 | 87 | Yes |
| Latin, Arabic, digits, punctuation | 17,000 | 11,000 | 116 | 112 | No |
| Combining Latin, Arabic, Hebrew, emoji | 28,500 | 15,500 | 132 | 150 | No |
| Parentheses, Arabic, Hebrew, emoji | 25,000 | 17,000 | 177 | 175 | No |

The second case diverges at UTF-16 offset 97: TextKit wraps 94 units while Core Text wraps 98. The combining-script case diverges on its first line (116 units in TextKit, 104 in Core Text). Matching the issue's repeated Arabic/emoji fixture therefore does not generalize to mixed-script text.

## Interpretation

The current Core Text line map cannot safely define NoteHush's native scroll positions or caret geometry for arbitrary text. This control does not test the 10 MiB fixture or an integrated editor; it is a small generated-data equivalence check. The mismatch is enough to reject this mapping strategy as a product correction under issue #75's requirement to preserve native layout semantics. No fallback, file-size restriction, paragraph insertion, or product-source change was made.

The standalone source is [`CoreTextNativeGeometryControl.swift`](reproducers/CoreTextNativeGeometryControl.swift). It compiled with Swift 6.3.3 and passed `swift-format lint --strict`; its output retained per-case line counts, exactness booleans, geometry digests, and first differing ranges.

Source SHA-256: `20812600240139b046e271a07d8cab96b2941abd86c19b64026407594695c365`.
Binary SHA-256: `170e5049dcab167775fe40a7a53b1a9ea445bc6ac42277537df269d48f0b1742`.
