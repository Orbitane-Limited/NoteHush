# Native line-aligned chunk planner prototype

Issue #75 remains unresolved. This generated-data experiment evaluates whether a custom TextKit 2 content manager could split a very long paragraph at native soft-line boundaries, then render each piece as an `NSTextParagraph`. It does not change application source.

## Bounded-window planner

The planner lays out at most 4,096 UTF-16 units at a time using `NSTextContentStorage` and `NSTextLayoutManager` at an 858-point container width. It ends each piece at the last complete native line in the window, yields to the main actor between windows, and keeps exact UTF-16 coverage.

The four complete small-fixture comparisons matched native TextKit line starts, lengths, and typographic-width bit patterns exactly:

| Generated fixture | UTF-16 units | Chunks | Native lines | Exact geometry |
| --- | ---: | ---: | ---: | --- |
| Arabic + emoji | 8,000 | 2 | 87 | Yes |
| Latin, Arabic, digits, Hebrew, emoji | 11,000 | 3 | 116 | Yes |
| Combining Latin, Arabic, Hebrew, emoji | 15,500 | 4 | 132 | Yes |
| Arabic/Hebrew punctuation and parentheses | 17,000 | 5 | 177 | Yes |

The 10 MiB generated fixture is exactly 10,485,760 UTF-8 bytes and 5,242,888 UTF-16 units, with SHA-256 `e4e0a3ac39ad74b9b5d4b0b6c85e46ba7d1ea2f6c7ddd4c287f0e1e07effdd63`. On this arm64 Mac, the planner covered all units in 13.326 seconds across 1,296 windows and 56,989 lines. A 16 ms main-actor heartbeat advanced 439 times. The slowest measured window was 11.65 ms; nearest-rank p95 was 10.72 ms. These are one generated-data run, not repeated performance samples, and heartbeat ticks do not certify visible UI responsiveness.

## Editing and integration checks

A separate generated-data custom-manager probe successfully replaced text at a UTF-16 insertion point with an emoji and restored/redid it through an `UndoManager`; exact text comparisons passed. This exercised direct TextKit replacement calls, not a real keyboard event or input method.

The custom manager did not provide working native caret navigation. `NSTextSelectionNavigation` moved the test selection to document end; assigning a custom selection to the layout manager also triggered an AppKit location-type exception (`NSCountableTextLocation` compared with the probe's custom location). The probe has no production selection, mouse, IME, accessibility, find, printing, file, or recovery integration.

## Native TextKit chunk-manager control

A follow-up generated-data prototype used a custom `NSTextContentManager` to emit `NSTextParagraph` elements at the planner's native soft-line boundaries. The standard `NSTextLayoutManager` shaped those elements itself. All four small Unicode controls matched the original native TextKit line starts, lengths, and typographic-width bit patterns exactly.

On the same 10 MiB Arabic/emoji fixture, the planner produced 1,296 chunks and 56,989 lines in 13.676 seconds. A synchronous full-document layout then returned every line with exact planned geometry in 25.987 seconds. The result is complete, but full-document synchronous layout still exceeds the unchanged ten-second responsiveness target.

The custom manager then laid out 1,024-unit ranges at the beginning, middle, and end of the document. Those requests took 44.5 ms, 30.5 ms, and 22.7 ms, respectively. The twelve line rows intersecting each requested range matched the planner's source offsets, lengths, and width bit patterns exactly. These three targeted observations support further investigation of lazy viewport layout; they are not repeated performance samples or visible-frame measurements.

This prototype used a custom content manager and `NSTextLayoutManager`; it did not use `NSTextView`, provide an `NSView` editor surface, or test typing, mouse selection, caret navigation, undo, IME, accessibility, find, recovery, printing, or file lifecycle. It demonstrates a potentially useful native shaping boundary, not an application correction. Editing a chunk can invalidate its downstream line boundaries, and the asynchronous replanning and editor integration are not implemented. Issue #75 remains open.

Sources: [`NativeTextKitChunkedManagerSmallProbe.swift`](reproducers/NativeTextKitChunkedManagerSmallProbe.swift), [`NativeTextKitChunkedManagerFullProbe.swift`](reproducers/NativeTextKitChunkedManagerFullProbe.swift), and [`NativeTextKitChunkedManagerTargetedProbe.swift`](reproducers/NativeTextKitChunkedManagerTargetedProbe.swift). The full and targeted probes compiled with Swift 6/macOS 14 deployment target on arm64 macOS 26.6.2. Archived formatted source SHA-256 values: `078e835399aceac88fa3bdca31e290c134c79d96b0154af5b50b9558b57bb7a1`, `d248eb8742938aa4d55370e04456726c30c224d5012077f479b3f7ff334703f1`, and `7354ffeaa70d8c2d0f140d09add40fae5b63e0b5a1c97c3940867da74f360cca`. The full-run binary SHA-256 is `797a0295e6fb327e3cd726f719313239c644e2253951c21f9c48ea254bedc768`; the targeted-run binary SHA-256 is `5e3c734005d86d2273335cf6c197a42b6257161201ea545c7d59dbc765224072`.

Apple documents `NSTextView` as using `NSTextContentStorage`; a custom `NSTextContentManager` requires a custom `NSView` text surface ([TextKit overview](https://developer.apple.com/documentation/appkit/textkit)). The existing [direct-range viewport prototype](2026-10-29-custom-text-viewport-surface.md) demonstrates quick isolated layout and drawing for selected ranges, but its whole-document scroll controller remains slow and it does not provide an editor.

## Result

Line-aligned bounded layout is a promising way to keep individual native layout operations short. The complete 10 MiB planning pass takes more than 13 seconds. A [custom selection-navigation control](2026-10-29-custom-selection-navigation.md) now passes logical and line-level selection checks on small fixtures and targeted navigation/geometry checks around the midpoint and near the end of a generated 10 MiB fixture. Real event routing, viewport behavior, click/secondary-selection behavior at bidi boundaries, and older-OS direction handling remain unverified. This is diagnostic evidence only: issue #75 remains open, no shipping behavior or text limits changed, and no release-readiness claim is made.

Source: [`NativeLineAlignedChunkPlannerProbe.swift`](reproducers/NativeLineAlignedChunkPlannerProbe.swift), Swift 6, macOS 14 deployment target. Source SHA-256: `df066930e0e9a859e5ba971f54afd25da70a76655cf282fc137cd7cdf460399a`. Binary SHA-256: `2991eedb65e943e8cb76fd6187ea5d08dd3b67d068a6b21302e22080e2eba7de`.
