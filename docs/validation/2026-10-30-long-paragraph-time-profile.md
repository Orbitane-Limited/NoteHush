# Generated long-paragraph TextKit time profile

Issue [#75](https://github.com/Orbitane-Limited/NoteHush/issues/75) remains unresolved. This bounded profile examines only the generated-data `NativeSoftBreakDelegateProbe` already retained on this validation branch. It does not profile NoteHush or any unrelated process and does not change application code.

## Workload and environment

The probe assigned exactly 10,485,760 generated UTF-8 bytes: a 16-byte ASCII header followed by one unbroken Arabic/emoji paragraph. It then requested the first viewport from a TextKit 2 `NSTextView`. The profile began about one second after launch, after the probe logged `stage=assigned`, and sampled the exact child PID for four seconds at a 1 ms interval. The probe was then terminated by the harness; it had not returned from the synchronous layout request.

Environment: arm64 macOS 26.6.2, Xcode 26.6 (17F113). The hardware model was unavailable to the restricted shell. The generated-data process reported 1.5 GB current and peak physical footprint during this interval. This is a short diagnostic observation, not a product memory benchmark.

## Finding

The sample contained 3,391 stack samples. The main-thread layout stack accounted for 3,311 and remained inside `NSTextLayoutManager.ensureLayoutForBounds` → `NSTextLayoutFragment._layout` → `NSCoreTypesetter` → `CTTypesetterCreateWithAttributedStringAndOptions` → Core Text typesetter initialization and glyph shaping. The most common sampled work was `TTypesetter::FinishEncoding` / `TShapingEngine::ShapeGlyphs`; bidirectional reordering and font glyph-advance lookup also appeared below it.

The delegate's `shouldBreakLineBefore` callback had not fired when this profile was taken. The earlier bounded run of the same probe records no callback before its 12-second limit. This places the long delay before the proposed line-break callback and confirms that the native TextKit request is spending the sampled time constructing and shaping the paragraph typesetter. It does not establish a safe way to interrupt or partition that work while preserving paragraph-level Unicode behavior.

## Chunked Core Text comparison

A second generated-data control used the retained [`CoreTextChunkedParagraphProbe.swift`](reproducers/CoreTextChunkedParagraphProbe.swift), which creates one Core Text typesetter per fixed 65,536-UTF-16-unit slice. It covered all 5,242,888 UTF-16 units of the same 10 MiB source in 1.780 seconds and produced 55,842 lines. A one-second sample of that process reported a 52.8 MB current and peak physical footprint; its main-thread samples include Core Text typesetter construction and glyph encoding. This is a different work shape from constructing one typesetter for the full paragraph and shows that bounded typesetter input reduces the observed transient footprint substantially in this probe.

This fixed-slice strategy is not a correction: its 16 KiB control has 89 lines while native TextKit has 90, and native 10 MiB line geometry is unavailable for comparison. It cannot meet the exact layout, selection, editing, IME, undo, viewport, or recovery requirements by itself. The result is diagnostic evidence for further work on bounded shaping only.

## `NSTextView` with a custom chunked content storage

A further generated-data probe attached a custom `NSTextContentStorage` to a real TextKit 2 `NSTextView`, supplied 4,048-UTF-16-unit `NSTextParagraph` elements, and kept the original `NSTextStorage` as the editing source. A location-identity map was required because delegating unknown locations to `NSTextContentStorage.offset(from:to:)` caused an AppKit exception for null locations. The map and probe counter use `OSAllocatedUnfairLock`; this diagnostic compiled with Swift 6 and warnings treated as errors.

On the 10 MiB fixture with a 16-byte header paragraph, targeted ranges at the start, middle, and end returned in 0.170, 0.154, and 0.133 seconds, respectively. Each range was completely covered. These are three single runs on this Mac, including process startup and editor construction, and the fixture's repeated `خط📝` pattern happens to align with the selected fixed chunk size. They show that the custom manager can attach and answer these generated range requests quickly; they do not establish correctness for general text.

The geometry control explains why that limitation is decisive. With the header removed, the same repeated content forms one ordinary paragraph. Splitting it every 4,048 UTF-16 units still produced 90 rows for the 16,383-byte control, but did **not** match native TextKit: around chunk boundaries, native 92-unit lines became 91- and 93-unit rows, and later line starts shifted by one unit. The custom chunks therefore change visible wrapping on a valid single-paragraph input. The fixed chunking cannot ship.

On the headed 16 KiB control, a focused insertion near a chunk boundary followed by full relayout completed and Undo restored the original text. This was a programmatic probe with an unshown borderless window, not real keyboard input; it did not validate edit fidelity, caret navigation, IME, viewport scrolling, recovery, or the location map after arbitrary edit sequences. The custom-manager result remains investigation evidence only.

Retained reproducers: [`NSTextViewLineAlignedSafeLocationProbe.swift`](reproducers/NSTextViewLineAlignedSafeLocationProbe.swift) provides the header-fixture targeted-range and native-geometry controls; [`NSTextViewLineAlignedSingleParagraphProbe.swift`](reproducers/NSTextViewLineAlignedSingleParagraphProbe.swift) removes the header and reproduces the geometry mismatch. Both compile with the command below (substitute the source filename and output path):

```sh
xcrun swiftc -O -warnings-as-errors -parse-as-library \
  -target arm64-apple-macosx14.0 -swift-version 6 \
  -module-cache-path /private/tmp/NoteHushLineAlignedModuleCache \
  docs/validation/reproducers/NSTextViewLineAlignedSafeLocationProbe.swift \
  -framework AppKit -framework CryptoKit \
  -o /private/tmp/NSTextViewLineAlignedProbe
```

## Dynamic line planning and edit invalidation

The next probe derived each chunk boundary from Core Text's last complete line in a bounded window. With 4,096- and 8,192-unit windows, UTF-16 line starts and lengths matched native TextKit on four mixed-script controls. Core Text's own typographic-width bit patterns differed on three controls, but the subsequent TextKit `NSTextParagraph` integration reproduced exact pre-edit TextKit geometry on all four. Increasing the Core Text window to 16,384 units caused the combining-mark control to produce 150 lines where native TextKit produced 125. The 10 MiB line plan took 19.60 seconds at 8,192 units, 2.63 seconds at 16,384 units, and 2.36 seconds at 65,536 units in the latest run. Window cost is nonmonotonic: the fast sizes have not preserved combining-mark boundaries, while the small-control-safe 8,192-unit size misses the app bound. These are exploratory single-run measurements.

The integrated custom manager attached to `NSTextView` using public TextKit APIs, rendered exact pre-edit geometry for the four controls, inserted a generated character at a UTF-16 position, performed local relayout, and restored the original text through Undo. However, a subsequent full relayout with the original immutable plan no longer matched native geometry: the mixed-script, combining-mark and punctuation controls produced 220 vs. 112, 249 vs. 126, and 199 vs. 175 rows, respectively; the fourth control had equal row counts but different geometry. Editing invalidates the planned boundaries, so this static integration is not safe.

A follow-up used `NSTextLayoutManager.replace(_:)` to install a new custom content manager with a fresh plan after the edit while keeping the same backing `NSTextStorage`. The replacement remained attached; the UTF-16 caret survived replacement, and Undo restored both the original text and insertion caret on all four controls. Full post-edit geometry still differed from native TextKit on three controls. Replacing the manager removed duplicate fragments, but it did not make Core Text's replanned line boundaries match AppKit after those edits. This does not establish repeated-edit, real keyboard, IME, or viewport behavior.

On the 10 MiB headed Arabic/emoji fixture, the retained integrated probe planned 56,989 spans in 11.85 seconds with 4,096-unit windows. Targeted start, middle and end TextKit requests then completed in 0.29–1.81 ms and covered the requested ranges. A middle insertion matched generated text exactly, the immediate local layout call returned, and Undo restored the full original text. No post-edit geometry oracle was run on that large case; the small-control relayout failures above already reject the immutable-plan approach. The synchronous plan exceeds the unchanged 10-second app checkpoint deadline before recovery and other app work.

Retained sources: [`CoreTextDynamicLinePlanProbe.swift`](reproducers/CoreTextDynamicLinePlanProbe.swift) compares Core Text line boundaries with native TextKit across the four controls and measures 10 MiB planning at multiple window sizes; [`CoreTextPlannedNSTextViewEditReflowProbe.swift`](reproducers/CoreTextPlannedNSTextViewEditReflowProbe.swift) checks small-control geometry, editing, local relayout, Undo and the stale-plan failure; [`CoreTextPlannedNSTextViewReplaceManagerProbe.swift`](reproducers/CoreTextPlannedNSTextViewReplaceManagerProbe.swift) tests replanning and public content-manager replacement after an edit; [`CoreTextPlannedNSTextViewLargeEditProbe.swift`](reproducers/CoreTextPlannedNSTextViewLargeEditProbe.swift) measures the integrated 10 MiB targeted ranges and generated middle edit/Undo. These Swift 6 probes compile with `-warnings-as-errors`, `-target arm64-apple-macosx14.0`, and the AppKit/CoreText frameworks.

| Source | SHA-256 |
| --- | --- |
| [`CoreTextDynamicLinePlanProbe.swift`](reproducers/CoreTextDynamicLinePlanProbe.swift) | `0950c409d893fe3bf7091f117f4714485959afba83d6b4639bf38ec85ac8cf7e` |
| [`CoreTextPlannedNSTextViewEditReflowProbe.swift`](reproducers/CoreTextPlannedNSTextViewEditReflowProbe.swift) | `8543addab38c80471d1b5ff94c7409e519bf4c10e8784a4516c92566b60abb31` |
| [`CoreTextPlannedNSTextViewReplaceManagerProbe.swift`](reproducers/CoreTextPlannedNSTextViewReplaceManagerProbe.swift) | `449f8a9e11fa9683011b0de87d09cbc8db42af1ff20000e99f68fb7c4de48bc0` |
| [`CoreTextPlannedNSTextViewLargeEditProbe.swift`](reproducers/CoreTextPlannedNSTextViewLargeEditProbe.swift) | `012d49fd9003aef38beab2357f724076c8e27d0bc79be7eba239cdd292b6651f` |

This is a more complete public-API integration demonstration, but not an acceptable correction: paragraph planning blocks synchronously, and edits invalidate the geometry plan. Incremental replanning, caret/selection navigation, real keyboard and IME, visible scrolling, accessibility, recovery and the unchanged app-level protocol remain unverified. Issue #75 stays open; application behavior and source are unchanged.

## Reproduction and provenance

Compile the retained probe source and run the generated fixture with a bounded profiler attached to that process:

```sh
xcrun swiftc -O -parse-as-library -target arm64-apple-macosx14.0 -swift-version 6 \
  -module-cache-path /private/tmp/NoteHushSoftBreakCommittedModuleCache \
  docs/validation/reproducers/NativeSoftBreakDelegateProbe.swift \
  -framework AppKit -framework CryptoKit \
  -o /private/tmp/NoteHushSoftBreakCommittedProbe
```

The measured invocation was `NativeSoftBreakDelegateProbe 10485760 128`, followed one second later by `sample <that-child-pid> 4 -file <profile-path>`. Only that generated probe process was sampled.

| Artifact | SHA-256 |
| --- | --- |
| Probe source | `09051a32da0387dbddabfe2cd095a87b6f8c8b3d0c8fdbcf05ed967f62a11bf6` |
| Compiled probe | `ef4c3f709ab00a88a68f4e7e24a75f17ce6d09bd6b91ff3527a34a9ac304b5a2` |
| [Raw sample](profiles/soft-break-10mib-time-profile.txt) | `cfae3b2f378391707917262a501644b755a7f02ba1a18b72fec777bac47ff399` |

The chunked comparison compiled `CoreTextChunkedParagraphProbe.swift` in a temporary `main.swift` with Swift 6, optimization, and the macOS 14 deployment target. It ran as `CoreTextChunkedCoreTextProfileProbe 10485760 65536`; `sample` was attached to that child process for one second, beginning about 100 ms after launch.

| Artifact | SHA-256 |
| --- | --- |
| Chunked probe source | `c259b6e6df755058116fdad3495369d1bef0c5840aabed49d5dfaa38f22f09b1` |
| Compiled chunked probe | `7a4012bfa42aa8da68bf38948e77f4a451c1187bc0a78c2e4c1913b4a87687e7` |
| [Gzip-compressed chunked raw sample](profiles/coretext-chunked-10mib-time-profile.txt.gz) | `972890a56c83ffdd569532428cd1b70367ec8cfc152b482d8964bb1abb78f639` |

Decompressing the chunked sample reproduces SHA-256 `fb5177033b22ce7532ab7a6dbadad9539769e069da91b73e1d559c6336ff82a9` exactly.

The raw sample contains system stack and process metadata only; the source document was generated. No user file was read. This profile supports the TextKit/Core Text shaping diagnosis but is not an unprofiled performance result, an app-level acceptance pass, or a product correction. All #75 acceptance criteria remain open.

## Corrected editable chunk control — 2026-10-30

The initial edit/replan geometry failures above were not a valid comparison of matching text attributes: the probe created a monospaced source but left the `NSTextView`'s font and typing attributes at their defaults, then compared the edited view with a monospaced oracle. It also exposed each wrapped line as a separate `NSTextParagraph`. A corrected generated-data control now sets the view font and typing attributes to the source font and groups contiguous native-line ranges into bounded paragraph elements. The old probe outputs remain historical observations, but they do not establish that a correctly configured editor must diverge after edits.

The corrected [`CoreTextIncrementalNSTextViewProbe.swift`](reproducers/CoreTextIncrementalNSTextViewProbe.swift) compiled with Swift 6.3.3, optimization, warnings treated as errors, and the macOS 14 deployment target. On arm64 macOS 26.6.2 / Xcode 26.6, it compared complete TextKit line starts, UTF-16 lengths, and typographic widths before and after a programmatic insertion, manager replacement, and Undo:

| Generated control | UTF-16 units | Initial planned/native rows | Reflow windows | Edited geometry | Text, caret and Undo |
| --- | ---: | ---: | ---: | --- | --- |
| RTL Arabic and emoji | 120,000 | 1,305 / 1,305 | 1, converged at 67,621 | Exact starts, lengths and widths | Exact text; selection preserved; Undo restored text and caret |
| Mixed Latin, Urdu, Hebrew, punctuation and emoji | 121,000 | 1,223 / 1,223 | 8, no suffix convergence | Exact starts, lengths and widths after replanning through the remainder | Exact text; selection preserved; Undo restored text and caret |
| Combining marks, Arabic, Hebrew and emoji | 124,000 | 1,000 / 1,000 | 8, no suffix convergence | Exact starts, lengths and widths after replanning through the remainder | Exact text; selection preserved; Undo restored text and caret |

The companion [`CoreTextLargeNSTextViewProbe.swift`](reproducers/CoreTextLargeNSTextViewProbe.swift) integrates the same bounded paragraph elements with the generated 10 MiB target. One arm64 run planned 56,989 lines in 1.303 seconds. A middle insertion took 15.736 ms in the probe, local native reflow used one 2,048-unit window in 13.090 ms, and the edited range was laid out in 14.758 ms. Targeted start, middle and end requests covered their full ranges in 9.378, 6.922 and 0.971 ms. Text and caret were restored by Undo. These are single diagnostic timings with a programmatic edit, not 20-run physical-input measurements or a first-visible-frame result.

The 10 MiB case cannot be compared with complete native TextKit geometry because the native full-paragraph oracle does not finish within its existing diagnostic bound. The shorter controls support the grouped, line-aligned approach; they do not prove geometry for every 10 MiB Unicode input. Resize/font/wrap changes, real keyboard and IME input, Find, accessibility, recovery, save behavior, repeated edits during reflow, and normal app launch remain untested. No application source changed. Issue #75 remains open.

## Native reflow after edits — 2026-10-30

[`NSTextStorageObserverChunkProbe.swift`](reproducers/NSTextStorageObserverChunkProbe.swift) is a generated-data experiment with the app's `ParagraphDirectionPresenter`, grouped line-aligned `NSTextParagraph` elements, and a standard `NSTextView`. It checks complete native line starts, UTF-16 lengths, and typographic widths before and after an insertion. It is not application code and does not read files.

Updating only the custom elements' offsets and lengths keeps synthetic 10 MiB input events fast, but it is incorrect for mixed scripts: the 121,000-unit mixed Latin/Urdu/Hebrew control had 603 differing line records after one insertion. Replanning the affected grouped Core Text element did not correct that difference. The native bounded reflow control does match the full TextKit oracle on the 120,000-unit RTL/emoji, 121,000-unit mixed-script, and 124,000-unit combining-mark controls. Mixed-script and combining controls needed eight 8,192-unit windows and had no suffix convergence. Their complete reflow and full geometry comparison took approximately 190–192 ms in these single diagnostic runs. The RTL/emoji control converged after one window.

For the generated 10 MiB RTL/emoji target, the bounded observer prototype planned initial elements in 1.315 seconds. Twenty synthetic key events retained exact text, selection, targeted fragment coverage, and Undo, but event p95 was 21.1 ms. A capped 16-window native reflow did not converge after approximately 547 ms. Reflowing the entire edited suffix in 8,192-unit windows covered the complete document but took 10.982 seconds across 321 windows and found no reusable suffix. Increasing each window to 65,536 units reduced the count to 41 but took 53.529 seconds. A separate 65,536-unit mixed-script control matched geometry, then hit an AppKit temporary-attribute range assertion during Undo. These results reject both metadata-only updates and the measured larger-window strategy; they do not establish an acceptable live-edit correction.

The probe compiled with Swift 6, `-warnings-as-errors`, and the macOS 14 deployment target on arm64 macOS 26.6.2 / Xcode 26.6. These are single synthetic observations, not physical-input, minimum-hardware, memory, recovery, or release measurements. No product source changed and #75 remains open.

Reproduction (the full 10 MiB run uses the probe's 8,192-unit bounded control):

```sh
xcrun swiftc -parse-as-library -O -warnings-as-errors -target arm64-apple-macosx14.0 \
  -swift-version 6 -module-cache-path /private/tmp/NoteHushObserverProbeModuleCache \
  docs/validation/reproducers/NSTextStorageObserverChunkProbe.swift \
  App/NoteHush/Editor/ParagraphDirectionPresenter.swift \
  -framework AppKit -framework CoreText -o /private/tmp/NoteHushObserverChunkProbe
/private/tmp/NoteHushObserverChunkProbe 8192 400 8192
# To repeat the larger-window control:
/private/tmp/NoteHushObserverChunkProbe 65536 400 8192
# To repeat the mixed-script 65,536-unit small-control assertion (expected failure):
/private/tmp/NoteHushObserverChunkProbe 8192 16 65536
```

The executable arguments are large-run window size, large-run maximum window count, and small-control window size. The assertion reproduction is intentionally a failing control; its failure is retained rather than converted to success.

| Artifact | SHA-256 |
| --- | --- |
| [Probe source](reproducers/NSTextStorageObserverChunkProbe.swift) | `92cae5316164a5da351f9fd8570744066ea40925f12c2f1a58ddb7f9b1abed3f` |
| Compiled probe | `1511c011140070cc7f074819c9f852060bc902c4fdcb3891d71f0dd47c4aa74f` |

Reproduction (run each process separately):

```sh
xcrun swiftc -parse-as-library -O -warnings-as-errors -target arm64-apple-macosx14.0 \
  -swift-version 6 -module-cache-path /private/tmp/NoteHushIncrementalProbeModuleCache \
  docs/validation/reproducers/CoreTextIncrementalNSTextViewProbe.swift \
  -framework AppKit -framework CoreText -o /private/tmp/CoreTextIncrementalNSTextViewProbe
/private/tmp/CoreTextIncrementalNSTextViewProbe

xcrun swiftc -parse-as-library -O -warnings-as-errors -target arm64-apple-macosx14.0 \
  -swift-version 6 -module-cache-path /private/tmp/NoteHushLargeProbeModuleCache \
  docs/validation/reproducers/CoreTextLargeNSTextViewProbe.swift \
  -framework AppKit -framework CoreText -o /private/tmp/CoreTextLargeNSTextViewProbe
/private/tmp/CoreTextLargeNSTextViewProbe
```

| Artifact | SHA-256 |
| --- | --- |
| [Editable-control source](reproducers/CoreTextIncrementalNSTextViewProbe.swift) | `66b1f6df4d1cba7612e03f6972244e576dcc7f82883bb00c43f755c800b624f6` |
| Editable-control binary | `32e4cc98e29a22dcdaffbb6bbe2e7864c6809e96fbb3186f745686705ede7e88` |
| [10 MiB source](reproducers/CoreTextLargeNSTextViewProbe.swift) | `d9fbd855a541072398417610a64804144afc845130d75334e75a526e7072ea9f` |
| 10 MiB binary | `332177a3377baf939ee1b4ee5c16566a94771bd3caff7a42d3dcccbab780dc64` |

## Reusing the chunked editor's layout manager — 2026-10-30

The generated [`IncrementalChunkLayoutReuseProbe.swift`](reproducers/IncrementalChunkLayoutReuseProbe.swift) removes the prototype's layout-manager recreation after edits and invalidates the existing manager's document range. It uses the exact 10 MiB Arabic/emoji fixture, the same synthetic window-dispatched key events, generated edit/marked-text cases, and scroll-render oracle as [`IncrementalChunkEditProbe.swift`](reproducers/IncrementalChunkEditProbe.swift). Neither probe reads user files or changes application source.

Reusing the manager made synthetic key dispatch appear substantially faster: the passing control measured 29.10 ms p95, while the candidate measured 0.129 ms p95 after manager reuse. The candidate then failed at the first viewport render: zero layout fragments covered the requested range, the bitmap contained only its 2,000 nonwhite background pixels, and the probe exited with code 16. AppKit also logged calls to `documentRange` while the layout manager's content manager was nil. The lower input timings therefore do not represent a visible edit and are rejected.

The candidate compiled with Swift 6, optimization, and a macOS 14 deployment target. One fresh process completed in 7.718 seconds through the failed viewport assertion. It reported 2,495.55 ms initial construction, 1.67 ms first synthetic key dispatch, and 0.129 ms p95 over 20 repeated key events. These are single-run diagnostic timings, not latency acceptance measurements. The unchanged passing control took 8.563 seconds and reported 2,502.01 ms initial construction and 29.10 ms repeated-key p95.

| Artifact | SHA-256 |
| --- | --- |
| [Probe source](reproducers/IncrementalChunkLayoutReuseProbe.swift) | `681f8a52794970429c03dadfce93cd45b7b2f6317e1f74f9599c0cc1e4762eab` |
| Compiled candidate | `599a36ed80636a885e9a1a6e92b6a3b88ffc78ca0ad6f37b6c7c243c5d5942e2` |
| Candidate stdout (empty because the render oracle failed) | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| Candidate stderr | `f4e4f3b728382b73617d36fff607910e33b639af8d49692381d057c4a8bdab3d` |

This rejects layout-manager reuse in this prototype. Correct change notifications and line-fragment invalidation remain necessary to keep both input response and visible content correct; no production change is established and issue #75 remains open.
