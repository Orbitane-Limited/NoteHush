# Custom TextKit viewport surface prototype

Issue #75 remains unresolved. This generated-data prototype tests a public-API route beyond `NSTextView`: a custom `NSView` draws `NSTextLayoutFragment` values from a custom `NSTextContentManager`, while direct UTF-16 range requests tell `NSTextLayoutManager` which portion to lay out.

## Direct-range result

The fixture is exactly 10,485,760 UTF-8 bytes: `123456789012345\n` followed by repeated `خط📝`. It retains the original string and digest, uses a 14-point monospaced font, 858-point TextKit container, 868-point viewport, and 4,048-UTF-16-unit `NSTextParagraph` chunks. The prototype uses the exact generated-data file and compiled source in [`reproducers/CustomTextViewportSurfaceProbe.swift`](reproducers/CustomTextViewportSurfaceProbe.swift).

| Requested UTF-16 offset | Laid-out fragments | Range coverage | TextKit layout | Bitmap draw |
| ---: | ---: | ---: | ---: | ---: |
| 0 | 3 | 8,112 units | 56.3 ms | 14.9 ms |
| 2,621,440 (middle) | 3 | 12,144 units | 78.3 ms | 20.1 ms |
| 5,242,700 (near end) | 1 | 712 units | 4.1 ms | 2.8 ms |

All three runs report the same exact source digest: `e4e0a3ac39ad74b9b5d4b0b6c85e46ba7d1ea2f6c7ddd4c287f0e1e07effdd63`. These are single generated-fixture observations, not percentile measurements. The experiment demonstrates that direct range layout and bitmap rendering can be quick for selected portions of this fixture. It does not show an interactive viewport or editor.

## Scroll-controller failure

A 1.2-million-point document view with a 500-point viewport was scrolled to y=500,000 and asked to run `NSTextViewportLayoutController.layoutViewport()`. TextKit enumerated 1,298 content elements, produced 1,297 fragments covering the complete 5,242,888-UTF-16-unit source, and took 16.347 seconds in layout plus 9.138 seconds to draw. The bitmap remained the top-of-document image. Calling `relocateViewport(to:)` for the middle and end `NSTextLocation` values returned quickly with y positions 505,971 and 1,012,707 points. The subsequent `layoutViewport()` call then exceeded the unchanged 20-second process bound in both cases. The JSON observations retain these timeout outputs along with the direct-range and deep-scroll results.

Direct `ensureLayout(for:)` therefore avoids the whole-file walk only when the caller already supplies a logical text range. This prototype has not solved scroll-position-to-text-range mapping, and it does not render the deep-scroll result at the requested viewport.

## Integration limits

This is not an application change. The prototype does not support keyboard/mouse editing, `NSTextInputClient`, real IME composition, selection, undo, find/replace, accessibility, printing, recovery, or sandbox behavior. Chunk boundaries split the original paragraph into separate presentation elements; the source bytes stay unchanged, but equivalent native bidi/shaping behavior is not established for arbitrary text. The public custom-view route gives up behavior supplied by `NSTextView`; see Apple's [TextKit session](https://developer.apple.com/videos/play/wwdc2026/370/) and [`NSTextInputClient` documentation](https://developer.apple.com/documentation/appkit/nstextinputclient).

Source SHA-256: `14dd7d0f9f1c6683e36060392b33077194d5b6522cda626c0ce6072067a7b0df`; binary SHA-256: `5563a7092fb9ddd292fedf01f72bb20a754fe65f9940050020eaa24567239d08`. Environment: MacBook Pro 16,8, Apple M4 Pro, 24 GB, arm64, macOS 26.6.2, Xcode 26.6 (17F113), Swift 6.3.3. Compiler command: `swiftc -swift-version 6 -O -module-cache-path /private/tmp/NoteHushViewportModuleCache CustomTextViewportSurfaceProbe.swift -framework AppKit -framework CoreText`.
