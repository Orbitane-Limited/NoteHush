# Suspicious-content layout limit experiment

Issue #75 remains open. This generated-data-only follow-up tested whether TextKit 2's `limitsLayoutForSuspiciousContents` defensive mode improves long-paragraph layout in the virtual paragraph probe. The experiment changed no application code.

## Results

The probe generated the exact 10,485,760-byte Arabic/emoji fixture and ran 16 fresh-process cases with a 10-second bound: suspicious-content limiting on and off, unchunked and 4,032 UTF-16-unit paragraph elements, and full, first-text, middle, and end requests.

With unchunked content, the default setting timed out for all four requests. With the defensive setting, all four viewport requests timed out and the full-layout process terminated with exit code `-5` (signal 5); none returned layout data. With 4,032-unit elements, full-document layout timed out with either setting. The three viewport requests completed with either setting in 0.475–3.376 seconds, covering their requested UTF-16 ranges and producing identical per-range geometry digests for the two setting values. These are single-cell diagnostics, not performance percentiles, and elapsed times varied substantially between cells.

The flag therefore did not correct full layout or improve the chunked viewport result. For unchunked input, enabling it caused the process either to time out or terminate before it could report layout. This is consistent with Apple's warning that defensive handling can yield unexpected layout for a very long paragraph ([Apple documentation](https://developer.apple.com/documentation/appkit/nstextlayoutmanager/limitslayoutforsuspiciouscontents)).

## Application relevance

The current editor uses `NSTextView` backed by TextKit 1's `NSTextStorage` and `NSLayoutManager` in [EditorTab.swift](../../App/NoteHush/Editor/EditorTab.swift). This experiment uses a separate TextKit 2 `NSTextLayoutManager` and a custom content manager, so the tested flag is not a drop-in change for the shipped editor. No application behavior or acceptance criterion was verified, and #75 remains unresolved.

The [numeric matrix](2026-10-23-suspicious-layout-limit.json) contains every cell outcome and successful numeric observation. Raw compiler output, JSONL observations, source copy and binary remain in the private artifact directory listed there. The source and runner are in [reproducers](reproducers/README.md).
