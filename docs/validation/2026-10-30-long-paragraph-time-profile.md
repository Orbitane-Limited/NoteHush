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

The next probe derived each chunk boundary from Core Text's last complete line in a bounded window. With 4,096-unit windows, UTF-16 line starts and lengths matched native TextKit on four mixed-script controls. Core Text's own typographic-width bit patterns differed on three controls, but the subsequent TextKit `NSTextParagraph` integration reproduced exact pre-edit TextKit geometry on all four. Increasing the Core Text window to 16,384 units caused the combining-mark control to produce 150 lines where native TextKit produced 125; window size cannot be increased without further boundary safeguards. In the retained probe run, the unheaded 10 MiB line plan took 2.04 seconds at 16,384 units and 2.47 seconds at 65,536 units; these are single observations and do not establish a stable performance result.

The integrated custom manager attached to `NSTextView` using public TextKit APIs, rendered exact pre-edit geometry for the four controls, inserted a generated character at a UTF-16 position, performed local relayout, and restored the original text through Undo. However, a subsequent full relayout with the original immutable plan no longer matched native geometry: the mixed-script, combining-mark and punctuation controls produced 220 vs. 112, 249 vs. 126, and 199 vs. 175 rows, respectively; the fourth control had equal row counts but different geometry. Editing invalidates the planned boundaries, so this static integration is not safe.

On the 10 MiB headed Arabic/emoji fixture, the retained integrated probe planned 56,989 spans in 11.85 seconds with 4,096-unit windows. Targeted start, middle and end TextKit requests then completed in 0.29–1.81 ms and covered the requested ranges. A middle insertion matched generated text exactly, the immediate local layout call returned, and Undo restored the full original text. No post-edit geometry oracle was run on that large case; the small-control relayout failures above already reject the immutable-plan approach. The synchronous plan exceeds the unchanged 10-second app checkpoint deadline before recovery and other app work.

Retained sources: [`CoreTextDynamicLinePlanProbe.swift`](reproducers/CoreTextDynamicLinePlanProbe.swift) compares Core Text line boundaries with native TextKit across the four controls and measures 10 MiB planning at multiple window sizes; [`CoreTextPlannedNSTextViewEditReflowProbe.swift`](reproducers/CoreTextPlannedNSTextViewEditReflowProbe.swift) checks small-control geometry, editing, local relayout, Undo and the stale-plan failure; [`CoreTextPlannedNSTextViewLargeEditProbe.swift`](reproducers/CoreTextPlannedNSTextViewLargeEditProbe.swift) measures the integrated 10 MiB targeted ranges and generated middle edit/Undo. These Swift 6 probes compile with `-warnings-as-errors`, `-target arm64-apple-macosx14.0`, and the AppKit/CoreText frameworks.

| Source | SHA-256 |
| --- | --- |
| [`CoreTextDynamicLinePlanProbe.swift`](reproducers/CoreTextDynamicLinePlanProbe.swift) | `f2fb6dea9764491072f872c32c505d8a52e6a5afd33062b05b00bbe2120d29d5` |
| [`CoreTextPlannedNSTextViewEditReflowProbe.swift`](reproducers/CoreTextPlannedNSTextViewEditReflowProbe.swift) | `8543addab38c80471d1b5ff94c7409e519bf4c10e8784a4516c92566b60abb31` |
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
