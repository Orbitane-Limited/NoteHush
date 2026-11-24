# Core Text line-indexed viewport prototype

Issue #75 remains unresolved. This generated-data prototype tests whether a custom `NSView` can map a vertical scroll offset to a UTF-16 range, ask TextKit to lay out only that range, and draw the returned fragments in a viewport.

## Measurement

The fixture is exactly 10,485,760 UTF-8 bytes: a 16-byte header followed by repeated `خط📝`. A chunked Core Text pass builds 56,989 line records at the app's 858-point text width. The prototype uses those records to choose a starting text range, requests a 2,800-point prefetch margin and 180 more line records, lays out the matching `NSTextParagraph` chunks through `NSTextLayoutManager.ensureLayout(for:)`, then draws fragments clipped to an 868-by-500 bitmap viewport.

| Requested vertical position | Mapped UTF-16 offset | Line-index build | Range layout | Draw | Fragments intersecting viewport |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 0 | 0 | 1.651 s | 112.7 ms | 8.4 ms | 2 |
| 500,000 | 2,579,604 | 1.674 s | 113.7 ms | 14.3 ms | 2 |
| 1,010,000 (near end) | 5,225,708 | 1.823 s | 106.3 ms | 8.5 ms | 1 |

All runs preserved the same 10 MiB source digest: `e4e0a3ac39ad74b9b5d4b0b6c85e46ba7d1ea2f6c7ddd4c287f0e1e07effdd63`. They produced visible nonwhite bitmap pixels at each position. These are single generated-fixture measurements, not performance percentiles. The full line-index pass takes longer than the PRD's one-second 10 MiB opening target when run synchronously; background indexing and immediate input were not tested.

## What this establishes

Unlike `NSTextViewportLayoutController.layoutViewport()`, which walked all 1,298 content elements in the deep-scroll control, a caller-supplied line-index mapping let the custom view request a range near the viewport and keep TextKit layout around 0.11 seconds. The middle and end ranges were reached without laying out the entire 10 MiB source through TextKit. The exact numeric observations are in [`2026-10-29-range-mapped-scroll.json`](2026-10-29-range-mapped-scroll.json); the standalone generated-data reproducer is [`CustomTextRangeMappedScrollProbe.swift`](reproducers/CustomTextRangeMappedScrollProbe.swift).

The content manager divides the source into 4,048-unit paragraph elements. The line index uses separate 64,768-unit Core Text typesetters. Both chunk sizes are tailored to this repeated fixture; matching native TextKit geometry for arbitrary user documents is not established. TextKit's fragment frames and Core Text's accumulated heights also differ slightly, and only one or two fragments intersect each tested viewport. Pixel geometry, scrolling continuity, selection and cursor behavior remain unverified.

## Product integration remains incomplete

This prototype changes no application code. It does not implement `NSTextInputClient`, keyboard/mouse editing, real IME composition, selection rendering, undo, accessibility, find/replace, printing, recovery, or sandboxed app behavior. It does not demonstrate typing into the visible range or preserving caret/scroll while edits invalidate the line index. The custom `NSView` path still requires those parts before it can replace `NSTextView` in NoteHush.

Source SHA-256: `d17697afb7d7fcf182d46024e3cd1ea83d28204beb56d67c148a7fa2442fdaf8`; binary SHA-256: `cfc9fe510348b1f94b97a415c01395ddd59cbdd45774f3f57e3111616e593885`. Environment: MacBook Pro 16,8, Apple M4 Pro, 24 GB, arm64, macOS 26.6.2, Xcode 26.6 (17F113), Swift 6.3.3. The full JSON records inputs, text digests, mapped ranges, fragment coverage, timing, pixel counts and bitmap digests.
