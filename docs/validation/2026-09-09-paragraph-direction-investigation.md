# Paragraph-direction investigation and proposed editor change

Issue #45. Recorded 2026-09-09 UTC. Baseline main is `bb49b49c5cb3ead161f774d087d9fd26481f73e1`. The [complete diagnostic records](2026-09-09-paragraph-direction-investigation.json) retain every observation separately. This report does not replace the original application performance protocols or establish App Store readiness.

## Finding

The earlier interval-aligned app profile placed 508 of 572 main-thread samples in native bidirectional layout. A later forwarding layout observer recorded a 12-unit invalidation and only 24 newly generated glyphs while the native viewport layout still consumed about 30 ms. The public request range alone did not explain the cost.

A separate command-line diagnostic called Apple's public `CFAttributedStringGetStatisticalWritingDirections` with one complete paragraph. It alternated the full attributed document and an isolated copy of that same paragraph, keeping the requested text identical. Twenty observations of each representation and algorithm were collected for ASCII and mixed script at 256 bytes, 16 KiB and 1 MiB: 480 observations total. Every repeated result and full-document/paragraph result for the same algorithm matched, output bounds remained intact, and source strings remained unchanged.

| Statistical function input | Mixed-script median / p95 |
| --- | ---: |
| 256-byte document, one paragraph requested | 0.0082 / 0.0098 ms |
| 16 KiB document, one paragraph requested | 0.3803 / 0.4275 ms |
| 1 MiB document, one paragraph requested | 25.7268 / 26.7389 ms |
| Same paragraph alone, 1 MiB case | 0.0128 / 0.0150 ms |

This isolates input-size-dependent work in the framework function on this OS. It is not a claim about other OS versions or every document. The companion standard Unicode-direction function was also measured, but it implements different semantics and is not substituted for Apple's statistical behavior.

Apple documents the statistical function's paragraph-based rule and marks the API available from macOS 26 in the installed SDK. The [public function reference](https://developer.apple.com/documentation/corefoundation/cfattributedstringgetstatisticalwritingdirections(_:_:_:_:_:)) and SDK header were checked. The experiment uses no private API or interposition.

## Proposed public-API mitigation

The proposal uses the previously investigated TextKit 2 editor and its explicit viewport completion, plus `NSTextContentStorageDelegate`'s [paragraph-presentation callback](https://developer.apple.com/documentation/appkit/nstextcontentstoragedelegate/textcontentstorage(_:textparagraphwith:)). It resolves a natural paragraph's direction with the same Apple statistical function on a paragraph copy and supplies that resolved direction only in the presented `NSTextParagraph`. Its text and UTF-16 length stay identical to the original. The backing storage, typing attributes, undo history, recovery data and saved-file bytes are not restyled.

Explicit writing directions remain native. Nonuniform paragraph styles, nonuniform resolved directions and unavailable APIs use the standard native paragraph. A one-Mi-unit paragraph bound limits the two transient direction buffers to two MiB; larger paragraphs retain native presentation. There is no persistent cache of user text. The delegate and editor are main-actor isolated, including the delegate conformance.

A separate offscreen check covered 336 generated cases and 784 paragraphs: Arabic, Hebrew, Latin, combining marks, emoji, neutral content, direction isolates/embeddings and six newline forms, with natural and explicit paragraph directions. The callback preserved backing storage and all other attributes, matched the full-document statistical result and respected explicit directions. These checks are narrower than real IME, Find, accessibility and full application acceptance.

## Workspace diagnostics

Each private workspace case preserved two 1 MiB buffers, 20 app-local key/Undo observations, exact UTF-16 selections, independent logical viewport/offsets and a final complete recovery checkpoint. It retained the existing 20-second host and 30-second outer bounds. No global input or clipboard was used. Native engine checks excluded legacy fallback.

| Separate private variant | ASCII median / p95 | Mixed-script median / p95 |
| --- | ---: | ---: |
| Initial attributed storage assignment, TextKit 1 | 3.101 / 3.504 ms | 33.938 / 35.495 ms |
| Detach layout manager during initial assignment, TextKit 1 | 2.817 / 4.423 ms | 41.657 / 42.814 ms |
| TextKit 2 with paragraph presentation | 2.456 / 2.997 ms | 3.126 / 4.239 ms |

All 120 observations passed their original assertions. The first two variants were not adopted. The paragraph variant's mixed workspace reached its loaded stage in 0.153 seconds; that stage excludes parts of process launch and is not the PRD launch interval. Its generated editor image retained native RTL presentation and a visible caret.

The earlier unchanged TextKit 2 workspace had a mixed p95 of 57.764 ms, but these separately collected private observations do not establish a controlled production speedup. The unmodified complete launch and interaction protocols, including all samples and baseline controls, are still required. In particular, 4.239 ms synchronous app-local dispatch is not physical event-to-visible latency.

## Integration failure and teardown correction

The production proposal and all test targets built successfully for the macOS 14 deployment target. A direct non-hosted AppKit unit run used a sanitized environment, a fixed 30-second per-case bound and 180-second whole-command bound. Its first three navigation cases passed; the hidden-20-tab case exceeded its bound. The exact source, test/app binaries, debug symbols and log were retained. No assertion or timeout was relaxed.

A separate stage-only copy of that case passed every original construction, hidden-layout, preference, text-identity, byte and selection assertion. Its constructors took about 0.045 seconds and its final verification stage was reached after about 0.094 seconds. This did not resolve the unit failure by itself.

A predeclared single-case diagnostic of the retained failed bundle sampled only its verified process for two seconds and kept the same 30-second bound. It also timed out. All 1,522 sampled main-thread stacks were beneath `NSScrollView` deallocation, after XCTest entered its autorelease/memory-check scope. Releasing the view hierarchy requested viewport geometry after the weak paragraph delegate had disappeared, returning to the expensive default statistical path. This is evidence about teardown, not slow hidden construction or an authorization failure.

The proposed correction detaches the document view in an isolated editor deinitializer while explicitly keeping its paragraph presenter alive. A regression retains the views across model release and checks detachment, exact text, selection and continued modern-engine identity. Validation of this corrected proposal is recorded separately; the original failed run remains failed.

## Corrected AppKit results

After the teardown correction, all 38 cases ran within the same limits. Thirty-four passed; three tests exposed stale dirty state after Undo, and the new retained-view test observed actor-isolated destruction before its scheduled completion. All four failed assertions and the complete source/binaries were retained.

A generated callback counter confirmed the Undo issue: insertion produced one storage notification and one native text-change callback; Undo advanced the storage count to two and Redo to three, but the native callback count stayed at one. Exact text changed correctly while the untitled empty buffer incorrectly remained dirty after Undo. The correction observes the tab's own Undo/Redo completion notifications and consumes only a pending character edit already seen in storage. It updates revision, dirty state, metrics and checkpoint scheduling without duplicating a native callback's work. Existing reload, save-race and preference assertions remain intact; additional draft Undo/Redo and reload-Redo checks were added. The lifetime regression now runs in an async main-actor test and confines creation/release to its explicit autorelease scope, retaining the same detachment/text/selection assertions.

The corrected run, `DirectAppKit-95280B83-4436-46FE-9C90-8D369EEF39FC`, passed all **39 AppKit unit cases**, zero failures/skips, at 00:41:25–00:41:52 UTC. It includes the original file operations, failure handling, printed-PDF, preferences, hidden-layout, independent viewport/recovery, marked-text and Undo checks. Its source was uncommitted during collection; source hashes, complete test names and the exact bundle SHA-256 are retained in the numeric record. It used the same 30-second per-case/180-second total bounds and sanitized environment. It does not establish native UI automation or complete CI.

A final lifecycle review preserved any existing native content delegate and explicitly removed model observers/editor callbacks before view detachment. The final source rebuilt successfully and passed all 39 cases again in `DirectAppKit-27AF843C-1A32-4738-8153-8C1B051B2316` at 00:45:05–00:45:31 UTC, with the same bounds and no skips. All 45 repository tests, strict formatting and configuration checks passed. Both passing source variants and all earlier failures remain distinct in the numeric record.

## Clean-source builds and actual app recovery

The implementation was committed as `7281ad2db63ed6442f4dec9731c429c3f6fd3c2c`. The clean source passed all **85 core tests and 166 crash-recovery drills** (83 Debug and 83 Release), the Debug build, the universal Release archive and the optimized application/test-driver build at 00:50:31–00:51:45 UTC. Archive checks rejected shipping test probes; the optimized app retained exactly the four product sandbox entitlements. Commands, bounds, logs and hashes are recorded separately in `ParagraphHeadless-03919ABB-392B-42F3-A6B6-1C8A56609419` and the adjacent numeric record.

The same clean implementation also passed the complete original `ColdLaunchHarness` regression at 00:48:34–00:48:38 UTC in `ParagraphCold-BA5B4BDD-3554-4A1F-AF13-32EEA7931DB9`. The private host changes only failure retention and UUID recording; it retains every original assertion and ten-second observation bound. The run verifies mandatory workspace isolation, cold file requests, exact dirty/untitled/closed recovery, unchanged external bytes, and independent caret/viewport restoration across restart. The exact app binary and product entitlements remained unchanged before and after. This is a functional cold-launch check, not the optimized launch performance protocol or a signed installation check.

## Conditions and outstanding gates

M4 Pro/24 GiB, macOS 26.6.2 (25G83), Xcode 26.6 (17F113), macOS 26.5 SDK. The user reserved the Mac from 2026-09-08 22:04:56 through 2026-09-09 06:04:56 UTC. Native work and compilation were serialized; CI routing remained held because Automation Mode required owner authentication. Caches were warm. These were fresh diagnostic processes, not continuous thermal or energy observations.

Required UI automation, complete original performance protocols, macOS 14 runtime/Intel/M1 hardware, real IMEs/VoiceOver, final-head CI and release gates remain separate; the local universal archive passed as recorded above. No UI authorization policy was changed. Main, app version and release status remain unchanged by these experiments. An unavailable UI-test prerequisite does not convert these narrower checks into release acceptance.
