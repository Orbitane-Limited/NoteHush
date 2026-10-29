# Custom TextKit selection navigation control

Issue #75 remains unresolved. This generated-data control checks whether a custom `NSTextSelectionNavigation` can use the same custom UTF-16 locations as a line-aligned `NSTextContentManager`. It addresses the type mismatch observed when the earlier prototype used `NSTextLayoutManager.textSelectionNavigation` directly; it does not change NoteHush source.

## Result

The probe [`CustomTextSelectionNavigationProbe.swift`](reproducers/CustomTextSelectionNavigationProbe.swift) implements the public `NSTextSelectionDataSource` contract on the custom content manager, including value equality and hashing for generated UTF-16 locations. It creates `NSTextSelectionNavigation(dataSource:)` rather than using the layout manager's default navigation object. For caret geometry it delegates to `NSTextLayoutManager`'s own public selection-data-source implementation, preserving its visual-order leading/trailing edge flags instead of estimating caret positions itself.

All four generated fixtures passed checks for document-end movement, forward/backward composed-character boundaries, extending from the original selection anchor, paragraph and visual-line selection, native caret enumeration, point hit-testing through `NSTextSelectionNavigation.textSelections(interactingAt:)`, point-to-line mapping, and vertical navigation into the next line. The synthetic hit point returned a selection range inside the expected native line. Each tested visual line had two native caret edges per extended grapheme, one leading and one trailing, ordered by visual x. Forward and backward movement across every generated chunk boundary matched the adjacent grapheme boundaries. The combining-mark and supplementary emoji checks each advanced by two UTF-16 units. Chunked native TextKit geometry also matched the unsplit paragraph's line starts, lengths, and typographic-width bit patterns:

| Fixture | UTF-16 units | Chunks | Native lines | Exact geometry | Navigation |
| --- | ---: | ---: | ---: | --- | --- |
| Arabic + emoji | 8,000 | 2 | 87 | Yes | Pass |
| Latin, Arabic, digits, Hebrew, emoji | 11,000 | 3 | 116 | Yes | Pass |
| Combining Latin, Arabic, Hebrew, emoji | 15,500 | 4 | 132 | Yes | Pass |
| Arabic/Hebrew punctuation and parentheses | 17,000 | 5 | 177 | Yes | Pass |

The generated 10 MiB UTF-8 Arabic/emoji fixture also passed targeted navigation, paragraph/line selection, native caret-edge enumeration, point hit-testing and line mapping, and vertical movement at the midpoint and near the end of the document. The custom manager's shaped line rows matched the bounded planner exactly for both targeted chunks. Its 5,242,888 UTF-16 units were planned into 1,296 line-aligned chunks and 56,989 lines. Four diagnostic runs took 15.09, 13.58, 13.51, and 13.67 seconds; these observations span probe revisions, are not a performance benchmark, and do not establish interactive responsiveness. The selection control checked forward and backward movement around the midpoint chunk boundary. The 10 MiB diagnostic can be reproduced by adding `--ten-mib` to the executable command below.

The source compiled with Swift 6 and a macOS 14 deployment target on the local arm64 MacBook Pro 16,8 (M4 Pro, macOS 26.6.2, Xcode 26.6 / Swift 6.3.3). Reproduction from the repository root:

```sh
xcrun swiftc -parse-as-library -target arm64-apple-macosx14.0 -swift-version 6 -O \
  -module-cache-path /private/tmp/CustomTextSelectionProbeModules \
  docs/validation/reproducers/CustomTextSelectionNavigationProbe.swift \
  -framework AppKit -o /private/tmp/CustomTextSelectionProbe
/private/tmp/CustomTextSelectionProbe
```

Source SHA-256: `b697c14f14517078369f5b0768d57628cd56d653b5265bd5f675aa0284d9d265`. Binary SHA-256: `3f04f7c854eebe555f09bf4df1e9327a0675c2df6da81eeab59b193904d790c2`.

## Limits

This result removes one prototype-level selection-location mismatch and shows targeted shaping/navigation can work on the 10 MiB generated fixture; it does not resolve the 10 MiB long-paragraph responsiveness issue. Planning still takes more than 13 seconds, and this probe does not establish incremental editing or a functioning editor. The hit tests call TextKit's selection-navigation API with synthetic points and document-coordinate bounds; the probe does not exercise a visible viewport or actual mouse events. It also does not test real key events, IME composition, editing, undo, accessibility, find, printing, recovery, sandboxing, or file lifecycle. Although TextKit supplies both caret edges, the probe does not test secondary selection locations or affinity transitions at bidi boundaries. For natural paragraph direction, it uses Core Foundation's statistical direction API on macOS 26 and falls back to left-to-right on older systems, so this is not valid as the shipping direction policy for macOS 14. No layout strategy, paragraph structure, text limit, timeout, or shipping behavior changed. Issue #75 remains open.
