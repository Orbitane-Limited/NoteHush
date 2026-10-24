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

Three generated-data probes tested whether chunked text elements could keep `NSTextView` while avoiding the one-element 10 MiB paragraph. They ran on macOS 26.6.2, Xcode 26.6 (17F113), arm64, against the exact 10,485,760-byte fixture. None produced usable layout:

| Probe | Outcome |
| --- | --- |
| [`NSTextViewDelegateEarlyProbe.swift`](reproducers/NSTextViewDelegateEarlyProbe.swift) installs the element delegate before filling the text storage, matching app initialization | Delegate emitted two elements for the midpoint request, but returned no layout fragments; target coverage remained false. Installing the delegate earlier did not change the prior result. |
| [`NSTextViewCustomStorageInitializationProbe.swift`](reproducers/NSTextViewCustomStorageInitializationProbe.swift) connects a chunked `NSTextContentStorage` before constructing `NSTextView` | Signal 6 during fragment layout; `offsetFromLocation:toLocation:` received null locations. Constructing the view after storage setup did not avoid the mapping exception. |
| [`NSTextViewWithCustomManagerProbe.swift`](reproducers/NSTextViewWithCustomManagerProbe.swift) constructs `NSTextView` over the standalone chunked `NSTextContentManager` that succeeds in headless viewport layout | Signal 6 in `NSTextView.setTextContainer`; AppKit requested the manager's `textStorage` property, which the custom manager does not provide. |

These are failed probes, not proof that every `NSTextView` integration is impossible. They show that the tested public delegate/storage substitutions do not provide an editor with complete layout. Apple's [TextKit documentation](https://developer.apple.com/documentation/appkit/textkit) describes `NSTextView` as backed by `NSTextContentStorage` and presents an `NSView` custom text view as the route for custom content/layout control; the [WWDC26 TextKit session](https://developer.apple.com/videos/play/wwdc2026/370/) explains that a custom view must supply its own input, selection, rendering, accessibility and editing behavior. The currently tested path that lays out arbitrary requested ranges remains a separate custom `NSTextContentManager` and is not integrated into the app.

| Probe | Source SHA-256 | Binary SHA-256 |
| --- | --- | --- |
| Delegate before text assignment | `22876e11cc445f8d15d537794dc3ecf572eeff823b215ecb657703886724634d` | `129b01e68165b1021105d5e687cd5134af9a7d76ddf3365459ce7302ac677e13` |
| Custom storage before view creation | `881a8f9ce8c2c0dee5ca9b17a0c5c65b065654c597afab172476840f90fa27e3` | `b3a3ea8ab99f1dea79b1d584d47db066190d0b1dcc18c6635177cf4d774bc6dc` |
| Standalone custom manager in `NSTextView` | `48cc177337b62dfcc996a6d65c1c864de4f66f80d5929907d4ae8982d5a7cf82` | `f51ebae3df231a801b788e3ff6c77756118b9eb936084a3162f8f6647e0e9ac2` |

These generated-data integrations did not change the shipped app. They establish neither real input behavior nor a rendering correction; #75 remains open.
