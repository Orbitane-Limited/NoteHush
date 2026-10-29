# Custom TextKit selection navigation control

Issue #75 remains unresolved. This generated-data control checks whether a custom `NSTextSelectionNavigation` can use the same custom UTF-16 locations as a line-aligned `NSTextContentManager`. It addresses the type mismatch observed when the earlier prototype used `NSTextLayoutManager.textSelectionNavigation` directly; it does not change NoteHush source.

## Result

The probe [`CustomTextSelectionNavigationProbe.swift`](reproducers/CustomTextSelectionNavigationProbe.swift) implements the public `NSTextSelectionDataSource` contract on the custom content manager, including value equality and hashing for generated UTF-16 locations. It creates `NSTextSelectionNavigation(dataSource:)` rather than using the layout manager's default navigation object.

All four generated fixtures passed logical navigation checks for document end, forward/backward composed-character boundaries, extension from the original selection anchor, and paragraph selection. Forward and backward movement across every generated chunk boundary matched the adjacent grapheme boundaries. The combining-mark fixture advanced its first grapheme by two UTF-16 units; the supplementary emoji check also advanced by two. The same source compared chunked native TextKit geometry with the unsplit paragraph; line starts, lengths, and typographic-width bit patterns matched across all fixtures:

| Fixture | UTF-16 units | Chunks | Native lines | Exact geometry | Navigation |
| --- | ---: | ---: | ---: | --- | --- |
| Arabic + emoji | 8,000 | 2 | 87 | Yes | Pass |
| Latin, Arabic, digits, Hebrew, emoji | 11,000 | 3 | 116 | Yes | Pass |
| Combining Latin, Arabic, Hebrew, emoji | 15,500 | 4 | 132 | Yes | Pass |
| Arabic/Hebrew punctuation and parentheses | 17,000 | 5 | 177 | Yes | Pass |

The source compiled with Swift 6 and a macOS 14 deployment target on the local arm64 MacBook Pro 16,8 (M4 Pro, macOS 26.6.2, Xcode 26.6 / Swift 6.3.3). Reproduction from the repository root:

```sh
xcrun swiftc -parse-as-library -target arm64-apple-macosx14.0 -swift-version 6 -O \
  -module-cache-path /private/tmp/CustomTextSelectionProbeModules \
  docs/validation/reproducers/CustomTextSelectionNavigationProbe.swift \
  -framework AppKit -o /private/tmp/CustomTextSelectionProbe
/private/tmp/CustomTextSelectionProbe
```

Source SHA-256: `c0221ebe8f77605a8178bc1996868c1200ebccba9c85de07e83bbfa92735b6d0`. Binary SHA-256: `4c8c534878bf7e4c874dabaf661c1d3f915c6f10948efb2e07dc7bff37f7937c`.

## Limits

This result removes one prototype-level selection-location mismatch; it does not establish a functioning editor or resolve the 10 MiB long-paragraph stall. The probe does not exercise a visible viewport, actual key or mouse events, visual-line movement, hit testing, real IME composition, editing, undo, accessibility, find, printing, recovery, sandboxing, or file lifecycle. Its selection data source does not yet implement production-quality caret geometry and soft-line mapping. No layout strategy, paragraph structure, text limit, timeout, or shipping behavior changed. Issue #75 remains open.
