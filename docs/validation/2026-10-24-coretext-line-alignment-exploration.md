# Core Text line-alignment exploration

This generated-data diagnostic explores whether chunking a long paragraph can reduce the Core Text shaping cost while retaining TextKit 2 line geometry. It ran locally on arm64, macOS 26.6.2, Xcode 26.6 (17F113), Swift 6.3.3. It opened no user documents and changed no application source.

## Method and observations

The generated text is a 16-byte numeric header and newline followed by repeated `خط📝`, exactly 10 MiB in the large case. The app's 900-point editor frame with 16-point insets gives an 868-point text container; the 5-point TextKit line-fragment padding on each side leaves 858 points for Core Text line breaking. The Core Text probe keeps the header paragraph separate and uses body chunks aligned to the measured 92-UTF-16-unit line geometry: 4,048 units for the small reference and 64,768 units for the 10 MiB case.

For the 16 KiB generated fixture, the chunked Core Text result covered all 8,200 UTF-16 units in 90 lines. Its complete line records (document offset, UTF-16 length and typographic-width bit pattern) matched all 90 lines from a full TextKit 2 layout exactly. The two outputs were compared row by row; their digest formats differ, so hashes are not used as the equivalence assertion.

For the 10 MiB fixture, the chunked Core Text probe covered all 5,242,888 UTF-16 units in 56,989 lines in one 1.672-second observation. Its geometry digest is `d46be1b47cf066b3b7b32e7876e7452157dc127f78d92f6b83aa0a3acb5b489a`. Full native TextKit 2 geometry was not available for this size because the existing full-layout controls exceed their 12-second observation bound. The 1.672 seconds measures only this headless line-shaping diagnostic; it excludes file open, editor construction, recovery, input, rendering and interaction.

| Source | SHA-256 |
| --- | --- |
| [`CoreTextLineAlignedChunkProbe.swift`](reproducers/CoreTextLineAlignedChunkProbe.swift) | `61c37f0806338a6726961c1a71f81de4d4023fdef82d18dbf5dd3a9fa00d44b0` |
| [`VirtualParagraphViewportAppWidthProbe.swift`](reproducers/VirtualParagraphViewportAppWidthProbe.swift) | `510ace226904c39cac1fb9084595f3c49f40dd2cff486bbb96957862ab2c4f09` |

The compiled Core Text probe SHA-256 is `4e677dcde5af26fd06e3e97882970345e3c59890055f402ef5b2c51a4a08d619`; the compiled TextKit reference SHA-256 is `d922005e1ff578ab9b1cbd03cc24ab44ee008d010c2d860fadfc63da160fbb9e`. Commands were `swiftc -O -module-cache-path /tmp/NoteHushCoreTextModuleCache ... -framework AppKit -framework CoreText` and the equivalent TextKit compile, then `CoreTextLineAlignedChunkProbe 16384 4048 858`, `VirtualParagraphViewportAppWidthProbe 16384 20000 full false`, and `CoreTextLineAlignedChunkProbe 10485760 64768 858`.

## NSTextView integration control

The line-aligned geometry result was followed by a generated 16 KiB `NSTextView` integration control. Its `NSTextContentStorage` subclass emits the header paragraph separately, then uses 4,048-unit body elements aligned to the measured native line boundaries. The source compiled, but the probe terminated with signal 6 before returning a usable fragment: AppKit raised `NSInvalidArgumentException` because `offsetFromLocation:toLocation:` received null locations. This is the same class of mapping failure seen in the earlier chunked-storage integrations; line-aligned ranges did not make the public custom-storage path usable in `NSTextView`.

The [probe source](reproducers/NSTextViewLineAlignedStorageProbe.swift) SHA-256 is `1efd145397527f7f91f3205e99068a3134c6f7814630ba1ba0adff8e7cd3c828`; compiled binary SHA-256 is `0d5ef7504bb1fd058499cb74fa619529201054ed2f9d6cd5dadd044d40a7ad40`. Full stdout/stderr and binary are retained under `/tmp/issue75-aligned-textview-probe/`; stderr SHA-256 is `41d9116207c2d162f6ea35964e6753b029e377aab503928a3d07eee1e26fafd7`. This is a failed diagnostic, not a product regression or a passing layout result.

## Follow-up chunk-size sweep

On the same local arm64/macOS 26.6.2/Xcode 26.6 host, the unchanged Core Text probe was compiled once with `swiftc -O -module-cache-path /tmp/NoteHushCoreTextModuleCache ... -framework AppKit -framework CoreText`, then run sequentially against the same generated 10 MiB fixture at width 858 points. Source SHA-256 remained `61c37f0806338a6726961c1a71f81de4d4023fdef82d18dbf5dd3a9fa00d44b0`; binary SHA-256 was `f9e6ef19c2339ca4ec4d594569ba48215fe95320c4da3ce91465dec6278f140d`.

| Body chunk (UTF-16 units) | Lines / coverage | Elapsed | Geometry digest |
| ---: | --- | ---: | --- |
| 32,384 | 56,989 / 5,242,888 | 1.688 s | `d46be1b47cf066b3b7b32e7876e7452157dc127f78d92f6b83aa0a3acb5b489a` |
| 16,192 | 56,989 / 5,242,888 | 1.646 s | `d46be1b47cf066b3b7b32e7876e7452157dc127f78d92f6b83aa0a3acb5b489a` |
| 8,096 | 56,989 / 5,242,888 | 27.084 s | `d46be1b47cf066b3b7b32e7876e7452157dc127f78d92f6b83aa0a3acb5b489a` |

All completed runs covered the full generated source and produced identical line geometry. The 8,096-unit run was much slower; the following 4,048-unit run was interrupted before it produced a result. These sequential single observations are exploratory and do not establish a repeatable performance relationship or an app-level improvement. They reinforce that smaller chunks are not automatically faster and that the one-second opening target remains unmet by this headless path.

## Limits

This shows a promising match for one small repeated Arabic/emoji fixture and a fast 10 MiB headless line pass. It does not show that chunked Core Text preserves native geometry for arbitrary Unicode, bidi controls, paragraph styles, font fallback or edits, and it does not compare the large case against full native layout. It does not implement or validate an editable text view, IME composition, selection, undo, viewport restoration, recovery, accessibility, scrolling, cancellation or sandbox behavior. The 10 MiB observation also exceeds the PRD's one-second opening target even before app and file costs.

No product change is justified by this control alone. Issue #75 remains open until a supported correction passes the unchanged app-level performance, Unicode, editing, recovery and lifecycle gates.
