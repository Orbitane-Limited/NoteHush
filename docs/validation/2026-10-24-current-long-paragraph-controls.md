# Current long-paragraph candidate controls

Issue #75 remains open. These generated-data-only controls ran on the local arm64 Mac using macOS 26.6.2 and Xcode 26.6 (17F113). They compare the shipping TextKit 2 APIs on the same repeated Arabic/emoji paragraph. They open no window, read no user file, and send no input.

## Current app recheck

The current `7af3285` app code was built and signed with the exact product sandbox on hosted workflow [40068154831](https://github.com/Orbitane-Limited/NoteHush/actions/runs/40068154831). Source `a508a97d189b61cdbe61800f26692e4b825c9748` and app binary SHA-256 `5b32de5af2a5fd56eee758f18c2759b9fa0d3e742b034d4433c2045959646556` remained unchanged before and after the run. The exact 10,485,760-byte generated file SHA-256 is `e4e0a3ac39ad74b9b5d4b0b6c85e46ba7d1ea2f6c7ddd4c287f0e1e07effdd63`.

The app process failed the unchanged ten-second request-to-durable-checkpoint observation at **10.005845083 seconds**. The independent recovery reader did not verify a checkpoint, and the collector reported `checkpointTimeout`. The owned app identity and exact sandbox checks passed. The artifact remains at run artifact ID `12549963142`. This confirms the current candidate still has the #75 stall; it is one diagnostic observation, not a performance percentile. It did not capture an in-process sample.

## Exact-process timeout profile

The follow-up hosted run [40071304131](https://github.com/Orbitane-Limited/NoteHush/actions/runs/40071304131), source `088da1086be1f67a5dcca9b907fef825eba2e84d`, rebuilt the same unchanged app binary (`5b32de5af2a5fd56eee758f18c2759b9fa0d3e742b034d4433c2045959646556`) and sampled only the exact owned process after the original ten-second checkpoint deadline had failed. Request-to-checkpoint elapsed **10.019437167 seconds**; recovery remained unverified and the result remained `checkpointTimeout`. Signature, source and binary checks passed before and after the run.

The two-second Time Profiler sample captured 1,300 main-thread samples. All 1,300 reached `TTypesetter::FinishEncoding` → `TShapingEngine::ShapeGlyphs`; 1,298 reached `TRunGlue::NextRunRange` (99.846%). The callers show `NSTextLayoutManager` enumerating and laying out a fragment during `NSView layoutSubtreeIfNeeded`, invoked by `WorkspaceWindowController.presentSelectedTab()` while installing/selecting the file. This locates the observed stall in native paragraph shaping/layout on the main thread. It is one bounded profile of this generated fixture, not a general performance estimate. The sample has SHA-256 `3a2cde41d66aab2b32ba308b14e41327deae5cebd825cc86beb4aaf81571b094`.

## TextKit 2 base-direction control

The control uses standard `NSTextContentStorage` and `NSTextLayoutManager`, the app's 14-point monospaced font and 868-point text container. For `rtl`, a content-storage delegate returns a presentation paragraph with explicit right-to-left base direction while leaving the backing string and attributes untouched. Each mode ran in a fresh process with a twelve-second bound. The [exact Swift source](reproducers/TextKitBaseDirectionProbe.swift) and source/binary SHA-256 values are listed below.

| Exact UTF-8 size | Base direction | Elapsed | UTF-16 coverage | Lines | Geometry SHA-256 | Result |
| ---: | --- | ---: | ---: | ---: | --- | --- |
| 16,384 bytes | Natural | 77.952 ms | 8,200 / 8,200 | 90 | `345a42cbbe55877c43ba6e2656b238523a343c05c4ddec8fe4a3cdcd3aded3ad` | Complete |
| 16,384 bytes | Explicit RTL | 43.810 ms | 8,200 / 8,200 | 90 | `345a42cbbe55877c43ba6e2656b238523a343c05c4ddec8fe4a3cdcd3aded3ad` | Complete; same geometry |
| 10,485,760 bytes | Natural | 12-second bound | — | — | — | Timed out |
| 10,485,760 bytes | Explicit RTL | 12-second bound | — | — | — | Timed out |

All four processes preserved exact generated UTF-8 size. The small fixture had exact backing text and complete line coverage. Both large full-layout cells exceeded the twelve-second diagnostic bound; they are failed observations, not accepted timing samples. Explicit base direction therefore does not correct the large full-layout stall.

A separate call to `CFAttributedStringGetStatisticalWritingDirections` on the 10 MiB fixture completed in 80.476 ms and returned direction values `[0, 1]`. The current `ParagraphDirectionPresenter` requires all returned directions to be uniform and caps its paragraph range at 1,048,576 UTF-16 units; it would return `nil` for this fixture. Raising only that size cap would not make the existing presenter resolve this mixed paragraph, and forcing an RTL base in the separate TextKit 2 control still timed out.

| Probe | Source SHA-256 | Binary SHA-256 |
| --- | --- | --- |
| TextKit base-direction control | `d0332d9d1a562c9c6708659e457b3fdd17b6ac20b63359b452f9cb659b87731c` | `816145453b2cf34b69874c9c0c0e2694fdafa7ccd6e8656add99389b2b58cd01` |
| Core Foundation direction classifier | `df5486ca599d487caa12987de7a514439778f548f03b00df9aecd610d6357432` | `ed2ffd13466e6c7c45efe8be8367af398a7cfa720a1d97a91a3817e33b30f89a` |

These headless controls do not establish editing, IME, undo, viewport, recovery, resource bounds, physical-Mac performance or complete app behavior. The follow-up app profile confirms that native full-paragraph shaping remains the current candidate's hot path. No application behavior or release limit has changed.

## Framework text-view integration attempts

Four generated-data probes tested whether chunked text elements could keep `NSTextView` while avoiding the one-element 10 MiB paragraph. They ran on macOS 26.6.2, Xcode 26.6 (17F113), arm64, against the exact 10,485,760-byte fixture. None produced usable layout:

| Probe | Outcome |
| --- | --- |
| [`NSTextViewDelegateEarlyProbe.swift`](reproducers/NSTextViewDelegateEarlyProbe.swift) installs the element delegate before filling the text storage, matching app initialization | Delegate emitted two elements for the midpoint request, but returned no layout fragments; target coverage remained false. Installing the delegate earlier did not change the prior result. |
| [`NSTextViewCustomStorageInitializationProbe.swift`](reproducers/NSTextViewCustomStorageInitializationProbe.swift) connects a chunked `NSTextContentStorage` before constructing `NSTextView` | Signal 6 during fragment layout; `offsetFromLocation:toLocation:` received null locations. Constructing the view after storage setup did not avoid the mapping exception. |
| [`NSTextViewWithCustomManagerProbe.swift`](reproducers/NSTextViewWithCustomManagerProbe.swift) constructs `NSTextView` over the standalone chunked `NSTextContentManager` that succeeds in headless viewport layout | Signal 6 in `NSTextView.setTextContainer`; AppKit requested the manager's `textStorage` property, which the custom manager does not provide. |
| [`NSTextViewReplaceManagerProbe.swift`](reproducers/NSTextViewReplaceManagerProbe.swift) creates the standard editor first, then calls the public `NSTextLayoutManager.replace(_:)` with chunked `NSTextContentStorage` | Both the 16 KiB full-layout cell and 10 MiB viewport cell exited with signal 6. `NSTextLayoutFragment._layout` raised `offsetFromLocation:toLocation:` with null locations; replacing the manager after normal view initialization did not fix the mapping failure. |

These are failed probes, not proof that every `NSTextView` integration is impossible. They show that the tested public delegate/storage substitutions do not provide an editor with complete layout. Apple's [TextKit documentation](https://developer.apple.com/documentation/appkit/textkit) describes `NSTextView` as backed by `NSTextContentStorage` and presents an `NSView` custom text view as the route for custom content/layout control; the [WWDC26 TextKit session](https://developer.apple.com/videos/play/wwdc2026/370/) explains that a custom view must supply its own input, selection, rendering, accessibility and editing behavior. The currently tested path that lays out arbitrary requested ranges remains a separate custom `NSTextContentManager` and is not integrated into the app.

| Probe | Source SHA-256 | Binary SHA-256 |
| --- | --- | --- |
| Delegate before text assignment | `22876e11cc445f8d15d537794dc3ecf572eeff823b215ecb657703886724634d` | `129b01e68165b1021105d5e687cd5134af9a7d76ddf3365459ce7302ac677e13` |
| Custom storage before view creation | `881a8f9ce8c2c0dee5ca9b17a0c5c65b065654c597afab172476840f90fa27e3` | `b3a3ea8ab99f1dea79b1d584d47db066190d0b1dcc18c6635177cf4d774bc6dc` |
| Standalone custom manager in `NSTextView` | `48cc177337b62dfcc996a6d65c1c864de4f66f80d5929907d4ae8982d5a7cf82` | `f51ebae3df231a801b788e3ff6c77756118b9eb936084a3162f8f6647e0e9ac2` |
| Replace manager after view initialization | `45f5f8b7cf548384a4548c9dc806ee6ad53a8bf9c2af459946cadaaf79274331` | `fa82b5e77f42a074120a1df5a0378381097546c728ed08ee293e90117672ea12` |

The post-initialization replacement run is hosted workflow [40075923822](https://github.com/Orbitane-Limited/NoteHush/actions/runs/40075923822); the step preserves both signal-6 outcomes as data, so its successful workflow status is not a probe pass. Artifact ID `12553720377` (SHA-256 `97bc5add14e4ddaf876041603db287ba3ebd020f3efe19e8de8549d63db529f8`) retains both stdout/stderr pairs, source, binary and numeric result. These generated-data integrations did not change the shipped app. They establish neither real input behavior nor a rendering correction; #75 remains open.

## Chunk-boundary geometry control

The earlier viewport probes used a 900-point container; the app's 900-point editor frame with 16-point insets has an 868-point text container. To compare at that width, [`VirtualParagraphViewportAppWidthProbe.swift`](reproducers/VirtualParagraphViewportAppWidthProbe.swift) was run against the exact 16,384-byte generated fixture with natural direction, 14-point monospaced font, and complete layout. Standard `NSTextContentStorage` covered 8,200 UTF-16 units in 90 lines. The custom manager with one element for the Arabic/emoji paragraph also covered all units in 90 lines. Splitting that same paragraph into 4,032-unit or 4,030-unit `NSTextParagraph` elements covered all units in **91 lines**. The two chunked runs also returned different geometry digests from each other (`c52f35d5bfa5872178ddf3fcdc304ec6a0d31a8516463c32f3e6178bcfd3e1cd` versus `97e5d1f976d866fae883d90b64026478462d418146296570417e4077e7a2d0a6`).

This one generated fixture shows that dividing a long paragraph into fixed `NSTextParagraph` chunks can change wrapping geometry, even when the source text remains exact and the custom layout covers every UTF-16 unit. It does not prove that every adaptive chunking method fails. The custom 10 MiB viewport result remains a layout experiment; it does not demonstrate equivalent full-document layout or an editable app.

| Probe | Source SHA-256 | Binary SHA-256 |
| --- | --- | --- |
| 868-point container chunk geometry control | `3ef830220be0a8c86c5e4f6f6766ec7718d2b75d9559dd6c98b83c97de43cb05` | `b274b37b96d8f9364f4c097b16f0bde9585fc8060765aab0e8e241b53839dbb7` |

## Bounded Core Text chunking control

[`CoreTextChunkedParagraphProbe.swift`](reproducers/CoreTextChunkedParagraphProbe.swift) creates a fresh Core Text typesetter for each fixed UTF-16 chunk and requests line breaks at the app's 868-point content width. With the generated 10 MiB mixed paragraph, chunk size 4,032 produced complete UTF-16 coverage in **10.196 seconds**; chunk size 65,536 produced complete coverage in **1.849 seconds**. These are one observations each, not medians or p95. The 65,536-unit result still misses the PRD's one-second 10 MiB opening target. On the 16 KiB fixture, chunked Core Text returned 89 lines, compared with 90 from standard TextKit 2 at the same width; it does not establish equivalent native line geometry. The diagnostic preserves exact source text but does not implement editing, bidi-context continuity, selection, recovery, or a viewport.

| Probe | Source SHA-256 | Binary SHA-256 |
| --- | --- | --- |
| Core Text fixed-chunk shaping | `c259b6e6df755058116fdad3495369d1bef0c5840aabed49d5dfaa38f22f09b1` | `fa2f65d4db50ae8115a19af1bad38698baf6ef48eecba282a93a6363a70d0699` |

## TextKit 2 wrapping control

The generated [TextKit 2 wrap probe](reproducers/TextKit2WrapControlProbe.swift) mirrors the app's 14-point monospaced editor and 868-point wrapped content width. It compares complete layout with the app's wrapping geometry and the same container configured for horizontal scrolling. Each cell runs in a fresh process on the hosted `macos-26` runner with Xcode 26.6 and a fixed 12-second process bound. The fixture is exactly 16 bytes of header plus repetitions of `خط📝`; no user document or input is involved. The control does not change product code or file data.

Two independent runs, [40074939925](https://github.com/Orbitane-Limited/NoteHush/actions/runs/40074939925) and [40075577153](https://github.com/Orbitane-Limited/NoteHush/actions/runs/40075577153), compiled the same source (`d72b6c71aa707ccb24a857392b9d6b777fbb8bbe2c2873cc64aeeae7643d9b2f`) to the same binary (`4782f249a367cc38a4a564e3ec636f64addd8d10bb089ce748f4f73580c9e96e`). On both 16 KiB controls, TextKit covered all 8,200 UTF-16 units and preserved the identical generated text SHA-256 (`c1db91d3ffe1ba6fcfb96399af931a975f483d026e41bb7ba6ff17d3ce806c3a`). The wrapped runs laid out 90 lines in 152.796 ms and 208.422 ms; the no-wrap runs laid out two lines in 64.610 ms and 99.283 ms. Their geometry hashes differ as expected because the presentation widths differ.

At both 1 MiB and 10 MiB, wrapped and no-wrap full-layout processes all reached the unchanged 12-second diagnostic bound in both runs. These are eight failed cells, not completed layouts or latency samples. Removing word wrapping therefore does not resolve the long-paragraph shaping stall; no preference change is justified by this control. The result agrees with the app-only sample that located the stall in native glyph shaping, but the headless probe does not establish editor interaction, selection, IME, undo, viewport, recovery, or physical rendering.

Run 40074826928 is retained as a separate harness failure: the initial runner called `.upper()` on a UUID object before creating its artifact directory, so no probe cell executed. The runner fix was validated by the two complete matrix runs. The second run's compact artifact is `long-paragraph-wrap-4425a2cee884ca4223b47932cf56894dbc7fb3d5-1` (artifact ID `12553356045`, SHA-256 `e9ff062af35431b851559161b6f507033f5a8e5d0b7a4d7ea6dbf0f6d1ef6249`); its 30,096 bytes retain the source, binary, compile log, every cell's stdout/stderr and numeric result. The first complete run's raw artifact is also retained (ID `12551809901`, SHA-256 `57e35ea1582e14a0e3b14a79ee8fab9b8c4d3eb0b972011b561546b51e069f6f`). Neither run is a product acceptance result.

## Asynchronous fragment completion control

The bounded [fragment-queue probe](reproducers/TextKitFragmentQueueCompletionProbe.swift) tests the public `NSTextLayoutFragment.layoutQueue` path on a hosted `macos-26` runner. It creates a native `NSTextView` with the app's 868-point text-container width, a generated 10,485,760-byte fixture (16-byte header plus one unbroken Arabic/emoji paragraph), and a serial user-initiated layout queue. It runs the AppKit default event loop for up to 60 seconds, polling every 200 ms. The observer reads existing fragment state without requesting synchronous full layout. It logs only generated-text digests, numeric layout state, coverage and queue counts.

The corrected run [40078821677](https://github.com/Orbitane-Limited/NoteHush/actions/runs/40078821677) executed 300 polls across **60.602 seconds**. The generated UTF-8 remained exactly 10,485,760 bytes with SHA-256 `e4e0a3ac39ad74b9b5d4b0b6c85e46ba7d1ea2f6c7ddd4c287f0e1e07effdd63`. At the deadline, fragment states were `[3, 1]`: the header fragment was layout-available, while the mixed paragraph was still estimated. Only **16 of 5,242,888 UTF-16 units** were covered; the layout queue still reported **10 operations**. The 60-second observation therefore did not establish complete glyph layout. The workflow's diagnostic step correctly exited with failure because full contiguous coverage was not achieved; its evidence artifact is `12554362233` (`long-paragraph-fragment-queue-422f2ab1a1542707053e160c61f03e21e164580c-1`, 37,698 bytes).

The retained result JSON SHA-256 is `613b22192a6a48bfa168dd544b0adba4326983000adc8a73a9a2f625120eed68`; probe stderr SHA-256 is `9d206200624979d172ce1bb6d539b17f2f3777a16d57ccb142942f7311beb4a2`; source SHA-256 is `49549ca5359eec54d4b1d75dbde83d87b4d7634b0f76ea3802be3d897ef5ce07`; compiled binary SHA-256 is `8c7accec7ee7c07e6eeb486f1fdc775ed525640c565b66fb29b4026fad477ead`. Earlier attempts are retained separately: run `40078393645` observed the same incomplete paragraph but its shutdown did not return from `NSApplication.run`; run `40078640123` used an invalid Core Foundation run-loop mode and produced zero polls, so it is a harness failure, not a layout observation.

This headless generated fixture demonstrates that assigning the public asynchronous fragment queue kept the AppKit timer polling for one minute but did not complete this 10 MiB paragraph. It does not establish editor input, IME, undo, selection, recovery, sustained resource use, physical rendering or shipping-app behavior. No application source, limits or acceptance criteria changed.

## Native single-line field fallback

On 2026-10-29, a generated-data probe tested whether replacing `NSTextView` with a single-line `NSTextField` would avoid whole-paragraph shaping. It created exactly 10,485,760 UTF-8 bytes by repeating `خط📝`, configured the same 14-point monospaced font and 868-point width, assigned the full string, attached the field to an unshown borderless window, forced content layout, and rendered the field into an in-memory bitmap. The field's stored string remained byte-for-byte equivalent in all three cases.

| Cell configuration | Attach/layout | Draw | Total process |
| --- | ---: | ---: | ---: |
| Clipping | 2.877 s | 7.028 s | 9.919 s |
| Tail truncation | 2.514 s | 4.920 s | 7.375 s |
| Clipping with `NSCell.isScrollable` | 2.769 s | 6.770 s | 9.471 s |

String generation took 14–34 ms, field configuration 2–3 ms, and assigning the text 9–14 ms. The remaining cost is native layout and drawing; neither truncation nor the cell's scrolling setting provides a responsive fallback. This is a rendering-control observation, not an app comparison or latency percentile. It does not test live field-editor input, IME, undo, selection, accessibility, file recovery or sandboxed app behavior.

The field-editor activation branch of the same probe called `selectText(_:)` while its window was unshown; it terminated with signal 5 before producing output. This is retained as a harness failure and is excluded from the timing conclusions. The exact generated-data probe is [`NSTextFieldLongParagraphProbe.swift`](reproducers/NSTextFieldLongParagraphProbe.swift). Source SHA-256: `36248a13ddde85b929fa045dbfb4da9d404ed97c5338987b39450e9bf1b1526c`; binary SHA-256: `b327404a720a706ec048415b840d13145df8867dbceac8185ed12e967c93d93f`. Environment: MacBook Pro 16,8, Apple M4 Pro, 24 GB, arm64, macOS 26.6.2, Xcode 26.6 (17F113). The app source, product behavior and limits remain unchanged; #75 remains unresolved.
