# Custom TextKit selection navigation control

Issue #75 remains unresolved. This generated-data control checks whether a custom `NSTextSelectionNavigation` can use the same custom UTF-16 locations as a line-aligned `NSTextContentManager`. It addresses the type mismatch observed when the earlier prototype used `NSTextLayoutManager.textSelectionNavigation` directly; it does not change NoteHush source.

## Result

The probe [`CustomTextSelectionNavigationProbe.swift`](reproducers/CustomTextSelectionNavigationProbe.swift) implements the public `NSTextSelectionDataSource` contract on the custom content manager, including value equality and hashing for generated UTF-16 locations. It creates `NSTextSelectionNavigation(dataSource:)` rather than using the layout manager's default navigation object. For caret geometry it delegates to `NSTextLayoutManager`'s own public selection-data-source implementation, preserving its visual-order leading/trailing edge flags instead of estimating caret positions itself.

All four generated fixtures passed checks for document-end movement, forward/backward composed-character boundaries, extending from the original selection anchor, paragraph and visual-line selection, native caret enumeration, point-to-line mapping, and vertical navigation into the next line. Each tested visual line had two native caret edges per extended grapheme, one leading and one trailing, ordered by visual x. Forward and backward movement across every generated chunk boundary matched the adjacent grapheme boundaries. The combining-mark and supplementary emoji checks each advanced by two UTF-16 units. Chunked native TextKit geometry also matched the unsplit paragraph's line starts, lengths, and typographic-width bit patterns:

| Fixture | UTF-16 units | Chunks | Native lines | Exact geometry | Navigation |
| --- | ---: | ---: | ---: | --- | --- |
| Arabic + emoji | 8,000 | 2 | 87 | Yes | Pass |
| Latin, Arabic, digits, Hebrew, emoji | 11,000 | 3 | 116 | Yes | Pass |
| Combining Latin, Arabic, Hebrew, emoji | 15,500 | 4 | 132 | Yes | Pass |
| Arabic/Hebrew punctuation and parentheses | 17,000 | 5 | 177 | Yes | Pass |

The generated 10 MiB UTF-8 Arabic/emoji fixture also passed targeted navigation, paragraph/line selection, native caret-edge enumeration, point-to-line mapping, and vertical movement at the midpoint and near the end of the document. The custom manager's shaped line rows matched the bounded planner exactly for both targeted chunks. Its 5,242,888 UTF-16 units were planned into 1,296 line-aligned chunks and 56,989 lines. Three runs took 15.09, 13.58, and 13.51 seconds; these observations are not a performance benchmark and do not establish interactive responsiveness. The selection control checked forward and backward movement around the midpoint chunk boundary. The 10 MiB diagnostic can be reproduced by adding `--ten-mib` to the executable command below.

The source compiled with Swift 6 and a macOS 14 deployment target on the local arm64 MacBook Pro 16,8 (M4 Pro, macOS 26.6.2, Xcode 26.6 / Swift 6.3.3). Reproduction from the repository root:

```sh
xcrun swiftc -parse-as-library -target arm64-apple-macosx14.0 -swift-version 6 -O \
  -module-cache-path /private/tmp/CustomTextSelectionProbeModules \
  docs/validation/reproducers/CustomTextSelectionNavigationProbe.swift \
  -framework AppKit -o /private/tmp/CustomTextSelectionProbe
/private/tmp/CustomTextSelectionProbe
```

Source SHA-256: `223a4667da7bd82acd6eb7e4baef5ddb210604d16f3d0372424b1ae0f228278a`. Binary SHA-256: `047e86bb079022a8f82942eed2b663f6def89bc71f7090fa83575e5e1770e46b`.

## Limits

This result removes one prototype-level selection-location mismatch and shows targeted shaping/navigation can work on the 10 MiB generated fixture; it does not resolve the 10 MiB long-paragraph responsiveness issue. Planning still takes more than 13 seconds, and this probe does not establish incremental editing or a functioning editor. The caret and point checks call the selection data source directly; the probe does not exercise a visible viewport, actual key or mouse events, real IME composition, editing, undo, accessibility, find, printing, recovery, sandboxing, or file lifecycle. Although TextKit supplies both caret edges, the probe does not test click behavior, secondary selection locations, or affinity transitions at bidi boundaries. For natural paragraph direction, it uses Core Foundation's statistical direction API on macOS 26 and falls back to left-to-right on older systems, so this is not valid as the shipping direction policy for macOS 14. No layout strategy, paragraph structure, text limit, timeout, or shipping behavior changed. Issue #75 remains open.
