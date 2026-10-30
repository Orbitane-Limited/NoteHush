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

Before building the full index, a prefix-only plan for the first 8,192 UTF-16 units rendered 64 visible lines and 40,144 glyph pixels. Generated source preparation took 21.0 ms, and source preparation through the first captured viewport took 291 ms. This suggests a first-viewport-before-index sequence is fast enough in this isolated probe. It is only a bitmap-render measurement: the view does not accept text input, the window is not the NoteHush app, and disk reading, workspace restoration, and interactive input are not included. It does not establish the PRD's interactive-opening target.

The generated 10 MiB document had 5,242,888 UTF-16 units and 56,989 indexed lines. Index construction with a 65,536-unit window took 1.68 seconds in the latest run (recent single runs ranged from 1.68 to 1.75 seconds). Increasing the window to 262,144, 524,288, and 1,048,576 units took 1.83, 1.87, and 1.98 seconds in that run; earlier samples were as high as 2.08 seconds. At start, middle, and end, the scroll view reached the requested vertical offset, the corresponding source range was selected, native local layout took 9.9–36.1 ms in the latest run, and the captured viewport contained 39,090–40,842 dark glyph pixels.

## Planning speed follow-ups

The retained source compares the same input with a Core Text framesetter, which returns many line ranges per bounded slice rather than asking the typesetter for each break. It matched the per-line typesetter's line ranges and heights on all four Unicode controls and the 10 MiB generated document, but took 1.91 seconds in the latest run. Increasing the slice window did not help and took 1.83–2.08 seconds across recent runs.

Two height shortcuts were also measured on the repeated 10 MiB fixture. Measuring a font height once and assigning it to every line took 1.36 seconds but underestimated the document height by 56,988 points (968,813 vs. 1,025,801). Sampling a real line height every 64 lines took 1.37 seconds and was 63 points shorter than the measured plan. The sampled shortcut has not been validated across document styles and still exceeds the one-second target. None of these controls is a safe or sufficient correction.

For a 500-point viewport, 20 repeated midpoint native-slice layouts measured p95 of 9.90 ms for 28 lines, 11.89 ms for 32 lines, and 35.76 ms for 64 lines. All three produced visible glyph pixels in the captured viewport. The probe creates a fresh local TextKit 2 storage and layout manager for each sample; it does not include an edit, keyboard dispatch, selection update, IME, index update, or scroll input. The 28-line result makes a viewport-sized editing prototype worth exploring against the 16.7 ms target, but it does not establish typing latency or editor correctness.

A separate 20-sample control applied alternating insertions and deletions at the midpoint of a retained 28-line `NSTextStorage`, ensured the full local TextKit 2 range after every edit, and verified the source returned exactly to its original text. Relayout p95 was 9.70 ms (min 9.09, max 10.01 ms). The inputs were generated ASCII and emoji replacements. This shows that local storage edits can stay below the numerical 16.7 ms layout target in this slice. It does not dispatch keyboard events, exercise undo or real IME composition, reflow the global line index, capture edit pixels, restore recovery, or run inside NoteHush; it is not an end-to-end typing measurement.

## Limits

This result demonstrates a promising scroll-and-render primitive, not a shippable editor. It misses the PRD's one-second 10 MiB opening target because index construction alone took 1.68–1.75 seconds in the recent single runs. The probe does not test incremental index updates after edits, typing, IME, selection, undo, accessibility, find, save, recovery, memory limits, arbitrary document styles, or integration with NoteHush's editor. The generated case is one RTL/emoji paragraph. Do not treat this probe as closing issue #75 or as acceptance evidence for v1.

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
