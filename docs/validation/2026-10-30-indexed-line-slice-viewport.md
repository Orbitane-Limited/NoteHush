# Indexed line-slice viewport probe

This diagnostic tests whether a Core Text line index can provide scroll geometry for a generated large document while ordinary local TextKit 2 storages render only the visible slices. It runs outside the NoteHush app and opens no user files.

## Method

The probe builds a Core Text line index in bounded 65,536 UTF-16-unit windows, overlapping the last line at each window boundary. A standard `NSScrollView` contains an `NSView` with the indexed document height. At a requested vertical offset, the view selects 64 indexed lines, creates ordinary `NSTextStorage`, `NSTextContentStorage`, and `NSTextLayoutManager` objects for that slice, lays them out, and draws the native fragments at their indexed document position.

Small generated fixtures compare the index's UTF-16 line starts, lengths, and heights against full native TextKit 2. They cover RTL, mixed bidi, combining marks, punctuation, and LF/CRLF/CR/NEL/line-separator/paragraph-separator boundaries. For each fixture, separate slices at the start, middle, and end are laid out again using native TextKit and compared to the corresponding full-document line geometry. A 10 MiB generated RTL/emoji paragraph then requests the start, midpoint, and end of a real scroll view. The probe captures each viewport into a bitmap and counts dark glyph pixels.

## Result

The optimized Swift 6 build with warnings treated as errors succeeded on an Apple Silicon Mac. All five small generated fixtures matched native TextKit line starts, UTF-16 lengths, and heights. Native TextKit slices at the start, middle, and end also matched the full-document geometry exactly:

| Fixture | UTF-16 units | Lines | Largest Core Text/TextKit width difference | Height difference |
| --- | ---: | ---: | ---: | ---: |
| RTL and emoji | 8,000 | 250 | 0 pt | 0 pt |
| Mixed bidi | 13,200 | 300 | 6.74 pt | 0 pt |
| Combining marks | 13,800 | 225 | 3.20 pt | 0 pt |
| Punctuation and bidi | 20,400 | 450 | 7.75 pt | 0 pt |
| Hard line separators | 8,000 | 1,201 | 0 pt | 0 pt |

The width difference is between Core Text's typographic width and TextKit's line-fragment width; line boundaries and heights matched, and visible glyphs were drawn by TextKit. It remains a reason to avoid using Core Text widths as TextKit drawing geometry.

The hard-separator fixture includes all six supported endings. The native geometry helper converts each fragment's local UTF-16 line range to the full document coordinate by adding the text element's document offset. A sliced string that ends directly on a separator can produce an extra terminal empty TextKit fragment; the comparison excludes only that empty fragment at the slice boundary.

Before building the full index, a prefix-only plan for the first 8,192 UTF-16 units rendered 64 visible lines and about 40,000 glyph pixels. Generated source preparation took 21–22 ms; source preparation through the first captured viewport took 288–377 ms across recent single runs (356 ms in the latest run). This suggests a first-viewport-before-index sequence is fast enough in this isolated probe. It is only a bitmap-render measurement: the view is not inside NoteHush, and disk reading, workspace restoration, keyboard delivery and interactive opening are not included. It does not establish the PRD's interactive-opening target.

The generated 10 MiB document had 5,242,888 UTF-16 units and 56,989 indexed lines. Index construction with a 65,536-unit window took 1.68 seconds in the latest run (recent single runs ranged from 1.68 to 1.75 seconds). Increasing the window to 262,144, 524,288, and 1,048,576 units took 1.83, 1.87, and 1.98 seconds in that run; earlier samples were as high as 2.08 seconds. At start, middle, and end, the scroll view reached the requested vertical offset, the corresponding source range was selected, native local layout took 9.9–36.1 ms in the latest run, and the captured viewport contained 39,090–40,842 dark glyph pixels.

## Planning speed follow-ups

The retained source compares the same input with a Core Text framesetter, which returns many line ranges per bounded slice rather than asking the typesetter for each break. It matched the per-line typesetter's line ranges and heights on all four Unicode controls and the 10 MiB generated document, but took 1.91 seconds in the latest run. Increasing the slice window did not help and took 1.83–2.08 seconds across recent runs.

Two height shortcuts were also measured on the repeated 10 MiB fixture. Measuring a font height once and assigning it to every line took 1.36 seconds but underestimated the document height by 56,988 points (968,813 vs. 1,025,801). Sampling a real line height every 64 lines took 1.37 seconds and was 63 points shorter than the measured plan. The sampled shortcut has not been validated across document styles and still exceeds the one-second target. None of these controls is a safe or sufficient correction.

For a 500-point viewport, 20 repeated midpoint native-slice layouts measured p95 of 9.90 ms for 28 lines, 11.89 ms for 32 lines, and 35.76 ms for 64 lines. All three produced visible glyph pixels in the captured viewport. The probe creates a fresh local TextKit 2 storage and layout manager for each sample; it does not include an edit, keyboard dispatch, selection update, IME, index update, or scroll input. The 28-line result makes a viewport-sized editing prototype worth exploring against the 16.7 ms target, but it does not establish typing latency or editor correctness.

A separate 20-sample control applied alternating insertions and deletions at the midpoint of a retained 28-line `NSTextStorage`, ensured the full local TextKit 2 range after every edit, and verified the source returned exactly to its original text. Relayout p95 was 9.70 ms (min 9.09, max 10.01 ms). The inputs were generated ASCII and emoji replacements. This shows that local storage edits can stay below the numerical 16.7 ms layout target in this slice. It does not dispatch keyboard events, exercise undo or real IME composition, reflow the global line index, capture edit pixels, restore recovery, or run inside NoteHush; it is not an end-to-end typing measurement.

The `IndexedSliceView` input-client control applies 20 direct `insertText` callbacks to a 28-line slice, updates the backing 10 MiB generated string and local `NSTextStorage`, and ensures the slice's native TextKit layout after each change. Without concurrent indexing, callback-to-local-layout p95 was 11.97 ms (p50 11.75, max 12.17 ms). In six corrected controls the full 10 MiB background index started before those 20 callbacks; p95 was 12.47–13.26 ms (p50 12.10–12.51, max 12.79–13.48 ms). Indexing took 1.75–1.87 seconds, during which the main run loop completed 61–68 cycles after the callbacks. Exact resulting UTF-16 text and caret offset matched. A direct `setMarkedText` followed by `insertText` preserved exact composition text and selection. One explicitly grouped insertion followed by `UndoManager.undo()` restored the exact pre-edit text and caret.

Afterward, a separate hidden window attached an `NSTextInputContext` to the slice view. A generated `NSEvent.keyEvent` sent through the view's `keyDown(with:)` inserted the expected character. The process still cannot become key under its prohibited activation policy, and `NSApplication.sendEvent` did not dispatch to the hidden window. This verifies the view's direct AppKit input-context route, not application-wide event delivery or physical keyboard input. The headless call emitted `Connection invalid` XPC diagnostics while the direct route passed. Real IME, accessibility, incremental global-index repair, persistence and NoteHush integration remain unverified.

## Background indexing control

The probe runs the full 10 MiB Core Text index on a user-initiated dispatch worker, starts 20 direct editor callbacks while that work is active, then repeatedly services the main run loop until planning finishes. Six corrected optimized Swift 6 runs took 1.75–1.87 seconds and matched every foreground line range and height. The main run loop cycled 61–68 times after the callbacks, and direct callback-to-local-layout p95 was 12.47–13.26 ms. The probe exits normally. This shows the full-index computation can run away from the main thread without changing the tested line geometry, while this synthetic edit workload stays below 16.7 ms p95. It gives the app a way to show the first viewport before the complete index is ready, but does not reduce total index time or validate index updates after edits. The measurement is not a physical key event or visible app result.

An earlier `async` entry-point/`Task` variant printed its measurements and then crashed during process teardown with `EXC_BAD_ACCESS` in `objc_release` on the main thread, inside the async `main` epilogue. A subsequent dispatch worker with synchronous process teardown exits cleanly. The crash stack localizes the failure to async teardown, but does not establish the underlying object lifetime defect; that variant is not retained as a passing result or used by the app.

## Limits

This result demonstrates a promising scroll-and-render primitive and an off-main indexing control, not a shippable editor. The full index still takes 1.70–1.75 seconds; the first viewport took about 0.36 seconds in the isolated bitmap probe. The probe does not measure an interactive NoteHush window while indexing, incremental index updates after edits, real keyboard delivery, actual IME, selection navigation, accessibility, find, save, recovery, memory limits, arbitrary document styles, or app integration. The generated case is one RTL/emoji paragraph. Do not treat this probe as closing issue #75 or as acceptance evidence for v1.

## Standard `NSTextView` geometry follow-up

The earlier height-shortcut comparison used a plain TextKit 2 storage/layout-manager configuration, whose per-line reported heights were 18 points for the 14-point monospaced fixture. A standard `NSTextView` configured with its text container and inset reports 17-point vertical line positions. The distinction matters: the former is not the shipping editor's scroll geometry.

The updated diagnostic also laid out each complete small fixture in a standard `NSTextView`. Every UTF-16 line start and length matched the full TextKit source geometry, and every row's y coordinate matched a 17-point font-height stride. This held for RTL/emoji, mixed bidi, combining marks, punctuation, and all six hard line separators (including the empty rows produced by separators). Separate 28-, 32-, and 64-line `NSTextView` slices at the start, midpoint, and end of the 10 MiB paragraph matched the indexed UTF-16 ranges and stepped by 17 points. Thus a font-height stride is a plausible standard-`NSTextView` scroll model for these uniform-font fixtures; it is not validated for user-selected font sizes, font changes during planning, width changes, edits, or integration.

A further scroll-host control placed one real 32-line `NSTextView` as a child of a flipped full-height virtual document view. It replaced the view's bounded text storage and moved that same view to the indexed top, midpoint, and end slices. Each requested clip origin was exact (0, 484,406.5, and 968,313 points), the text in the view matched the corresponding source substring, and the bitmap contained visible text. Twenty additional moving updates of that same view measured 6.71 ms p50, 6.77 ms p95, and 6.88 ms max for storage replacement, local layout, and clip movement; every text and clip-origin check passed. These are synchronous generated-data measurements, not a real scroll-event or user-interaction benchmark. They show that a native editor view can be rebound across sampled scroll positions; they do not prove preservation of global selection/undo/IME semantics or complete accessibility and recovery.

The font sweep found that `ceil(ascent + descent + leading)` is not a correct native-editor scroll stride for every selectable font. It overestimated the actual `NSTextView` step by one point for 18- and 24-point system monospaced fonts and 14-point Menlo. Rounding each Core Text metric separately (`round(ascent) + round(descent) + round(leading)`) matched every enumerated line position for tested system monospaced sizes 9, 12, 14, 18, and 24, system 36, and Menlo 14; measured native steps were 11, 15, 17, 21, 28, 43, and 16 points respectively. This is a useful geometry correction for the probe, not broad coverage of every available font, fallback mix, paragraph spacing or changed font during a document session.

## Global source, Undo and typing follow-up

The reused-view host now treats the complete generated document as its local authority and synchronizes each `NSTextStorageDelegate` edit from the visible UTF-16 range into that source. A one-unit replacement in the middle slice updated the exact global source, grouped Undo restored the original full string, Redo restored the replacement, and moving to the start and back restored the text and global caret. Twenty subsequent same-length replacements each matched the expected full source; forced layout of the 32-line local view measured 7.09 ms p50, 7.52 ms p95, and 8.23 ms max. Grouped Undo and Redo again restored exact full-source states. This local-edit control does not verify its interaction with global suffix replanning or application recovery.

The isolated 20-call `NSTextView.insertText` control has variable headless timing: one run measured 21.38 ms p95 and a 46.39 ms cold/max, above the 16.7 ms target, while another measured 5.55 ms p95 and 11.98 ms cold/max. The integrated model-sync host control above stayed below the numeric target in its recorded run, but these tests use direct API callbacks, generated text, and a hidden window; real keyboard routing and physical responsiveness are still unverified. Preserve both results rather than treating the lower sample as the product's typing result.

The same 10 MiB run continued to pass direct `NSTextView.insertText` callbacks with a forced local `ensureLayout` after every insertion and exact Undo restoration. One run measured cold 12.47 ms, p95 5.95 ms, and max 12.47 ms across 20 inserts in a 28-line slice. This remains a direct API callback in a hidden headless window: it does not establish physical keyboard, application-wide event routing, real IME, or interactive latency.

A corrected native-stride run uses the rounded system-monospaced font metrics validated by the font matrix (17 points for this 14-point fixture) instead of Core Text's 18-point typographic line height. Its 10 MiB index height is 968,813 points, and the rendered native slices at the top, midpoint, and end now compare their local TextKit y positions against the global index. All three checks passed. The full `NSTextView` document is still not laid out; only bounded slices were verified.

The corrected run performs 13 independent edits to the generated paragraph: one-unit insertions and composed-character deletions at the start, 25%, 50%, 75%, and near the end; and composed-character replacements with ASCII at 25%, 50%, and 75% (the 25% and 75% replacements change UTF-16 length). Its restart point uses the pre-edit index: the line containing the edit with one line of lookback. It does not scan a new full plan to find the changed suffix. The full font-height plan is built only as a comparison oracle and took 1.45 seconds. Suffix replanning, including substring extraction, took 1.548/1.521 seconds at the start, 1.119/1.157/1.168 seconds at 25%, 0.724/0.769/0.792 seconds at 50%, 0.361/0.382/0.396 seconds at 75%, and 0.000256/0.000270 seconds near the end for insert/delete/replace where applicable. All 13 combined plans matched the full rebuild's line ranges, native-stride heights, and y positions. The width field is not measured in this font-height mode and is not claimed as validated. Exact line-boundary edits, cancellation, multiple fonts/styles, variable-wrap changes, and app integration remain untested. This is a promising index-update direction, not a product correction.

The corrected output was reproduced with optimized Swift 6.3.3, warnings as errors, Xcode 26.6 (17F113), macOS 26.6.2 arm64. Reproducer SHA-256: `40d10d7be0debac0f24a27283274ea075b65d5771b48477e90ed251f73d94072`. Raw output SHA-256: `ae1e4bb58f4040dae6d5268194d521e2b9f5191ed590f94afb3cbaca1fad9ae4`; see [the complete corrected output](2026-10-30-native-stride-suffix-replan-output.txt). The earlier Core Text typographic-height output remains retained separately. The probe uses no user files or input.

## Async suffix replan and concurrent edit follow-up

The reused native host now debounces document edits, plans the changed suffix on a detached worker, rejects a result whose source revision became stale, and merges the current result with the unchanged prefix. Each plan retains the exact segment starts used by its 65,536-unit Core Text windows; the next edit restarts from the prior stable segment, preserving the same bidi line breaks as a full rebuild. The native host, initial plan and oracle use the same 868-point text-container width.

On the 10 MiB generated RTL/emoji paragraph, the probe grouped 20 same-length native edits, verified grouped Undo and Redo against the complete source, then inserted another character while suffix planning was active. The stale result was discarded, the latest source revision was replanned, and the combined ranges, heights, y positions and segment starts matched the full-plan oracle. The concurrent native insertion took 8.179 ms; suffix replanning completed in 934.903 ms. The 20 direct native typing callbacks measured 7.316 ms p50, 7.447 ms p95 and 7.583 ms max. Twenty slice rebinds measured 6.616 ms p50, 6.899 ms p95 and 7.199 ms max. Start, midpoint and end clips showed visible glyphs and exact requested offsets. These are standalone generated-fixture measurements on this arm64 Mac, not measurements of the NoteHush app or physical keyboard latency.

Reproducer SHA-256: `ee9eca6a906b7589d1618604266bdb4f655f4bf2b7cda6bd02b1b3c59d6bf656`. Raw output SHA-256: `46a225f1e01b73f668846cdc2a1bcec617f02efd34feef4947a576481323e3e3`; see [the complete async output](2026-10-30-async-native-slice-output.txt). Built optimized with Swift 6.3.3 and warnings as errors using Xcode 26.6 on macOS 26.6.2 arm64.

This does not integrate the virtual host into `EditorTab`. Undo across a viewport rebind, IME composition, mixed fonts/paragraph styles, line-boundary edits, accessibility, recovery, variable-width changes and the supported macOS 14 runtime remain unverified. The example resolves RTL from this one generated fixture. The experiment establishes a promising public-AppKit path for further integration; it is not a product correction, and issue #75 remains open.

A follow-up attempt to ask a standard `NSTextView` to lay out and enumerate all 56,989 lines of the 10 MiB unbroken paragraph did not return within roughly one minute and was interrupted. It produced no full-document geometry result. This reinforces the need to keep work bounded to visible slices, but the successful slice measurements still do not establish safe app integration or exact full-document scrolling. No production code changed, and issue #75 remains unresolved.

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
