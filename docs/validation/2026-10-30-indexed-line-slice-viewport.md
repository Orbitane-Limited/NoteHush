# Indexed line-slice viewport probe

This diagnostic tests whether a Core Text line index can provide scroll geometry for a generated large document while ordinary local TextKit 2 storages render only the visible slices. It runs outside the NoteHush app and opens no user files.

## Method

The probe builds a Core Text line index in bounded 65,536 UTF-16-unit windows, overlapping the last line at each window boundary. A standard `NSScrollView` contains an `NSView` with the indexed document height. At a requested vertical offset, the view selects 64 indexed lines, creates ordinary `NSTextStorage`, `NSTextContentStorage`, and `NSTextLayoutManager` objects for that slice, lays them out, and draws the native fragments at their indexed document position.

Small generated fixtures compare the index's UTF-16 line starts, lengths, and heights against full native TextKit 2. For each fixture, separate slices at the start, middle, and end are laid out again using native TextKit and compared to the corresponding full-document line geometry. A 10 MiB generated RTL/emoji paragraph then requests the start, midpoint, and end of a real scroll view. The probe captures each viewport into a bitmap and counts dark glyph pixels.

## Result

The optimized Swift 6 build with warnings treated as errors succeeded on an Apple Silicon Mac. All four small generated fixtures matched native TextKit line starts, UTF-16 lengths, and heights. Native TextKit slices at the start, middle, and end also matched the full-document geometry exactly:

| Fixture | UTF-16 units | Lines | Largest Core Text/TextKit width difference | Height difference |
| --- | ---: | ---: | ---: | ---: |
| RTL and emoji | 8,000 | 250 | 0 pt | 0 pt |
| Mixed bidi | 13,200 | 300 | 6.74 pt | 0 pt |
| Combining marks | 13,800 | 225 | 3.20 pt | 0 pt |
| Punctuation and bidi | 20,400 | 450 | 7.75 pt | 0 pt |

The width difference is between Core Text's typographic width and TextKit's line-fragment width; line boundaries and heights matched, and visible glyphs were drawn by TextKit. It remains a reason to avoid using Core Text widths as TextKit drawing geometry.

The generated 10 MiB document had 5,242,888 UTF-16 units and 56,989 indexed lines. Index construction with a 65,536-unit window took 1.72 seconds. Increasing the window to 262,144, 524,288, and 1,048,576 units took 1.85, 1.89, and 2.02 seconds, respectively; each produced the same line count and total height. At start, middle, and end, the scroll view reached the requested vertical offset, the corresponding source range was selected, native local layout took 9.7–36.3 ms in the final run, and the captured viewport contained 39,090–40,842 dark glyph pixels.

## Limits

This result demonstrates a promising scroll-and-render primitive, not a shippable editor. It misses the PRD's one-second 10 MiB opening target because index construction alone took 1.70 seconds. The probe does not test incremental index updates after edits, typing, IME, selection, undo, accessibility, find, save, recovery, memory limits, arbitrary document styles, or integration with NoteHush's editor. The generated case is one RTL/emoji paragraph. Do not treat this probe as closing issue #75 or as acceptance evidence for v1.

Reproduce with:

```sh
mkdir -p /private/tmp/notehush-clang-cache
CLANG_MODULE_CACHE_PATH=/private/tmp/notehush-clang-cache xcrun swiftc \
  -module-cache-path /private/tmp/notehush-clang-cache -O -parse-as-library \
  -target arm64-apple-macosx14.0 -swift-version 6 -warnings-as-errors \
  docs/validation/reproducers/IndexedLineSliceViewportProbe.swift \
  -framework AppKit -framework CoreText -o /private/tmp/IndexedLineSliceViewportProbe
/private/tmp/IndexedLineSliceViewportProbe
```
