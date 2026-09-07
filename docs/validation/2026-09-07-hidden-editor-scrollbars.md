# Hidden-editor scrollbar layout investigation

Issue [#46](https://github.com/Orbitane-Limited/NoteHush/issues/46), version 0.1.0 (1). Legacy scrollbar auto-hiding causes premature first-paragraph layout during initial text assignment. The fix delays auto-hiding until the tab's normal scroll restoration, preserving native scrolling, the empty-first attachment order and the existing zero-layout assertions.

## Reproduction

[PR #44 CI 34099345754](https://github.com/Orbitane-Limited/NoteHush/actions/runs/34099345754) failed 39 assertions across two AppKit cases: 20 newly constructed editors and 19 hidden recovered editors reported first-unlaid UTF-16 index 16 instead of zero. Its editor source and these tests were identical to main `2c786fac01a59e548475c20f985050c0a430e992`. That CI run did not record its native scrollbar style, so the later reproduction identifies a sufficient trigger without claiming the run's style or a display-related cause. Its eight separate UI timeout/signal-kill outcomes remain tracked by #29.

Bounded offscreen AppKit probes ran on the M4 Pro/24 GiB Mac, macOS 26.6.2, Xcode 26.6 and Swift 6.3.3. They used only generated text, displayed no windows, accepted no input and touched no recovery store. The initial probes ran after CI's native stage ended, while artifacts uploaded; later native tests ran after CI fully completed. These are layout-state diagnostics, not performance timings.

The probes configured each instance's scrollbar style before attaching the empty editor and assigning text. With the original construction order:

| Fixture | Overlay + auto-hide | Legacy + auto-hide | Legacy without auto-hide |
| --- | ---: | ---: | ---: |
| 256 KiB mixed-script CRLF draft, 16-unit first paragraph | 0 | 16 | 0 |
| Unbroken mixed-script paragraph, 40,960 UTF-16 units | 0 | 40,960 | 0 |

Values are `firstUnlaidCharacterIndex()` immediately after assignment, not elapsed time. Replacing the storage directly also triggered legacy layout and changed the default font in one probe, so that alternative was rejected. Attaching populated text was not adopted because #39 already demonstrated its expensive bidirectional-layout path.

The final regression uses the actual `EditorTab(snapshot:scrollerStyle:)` constructor. The optional instance override is set before attachment/restoration; normal callers retain the system-selected style. Against the original auto-hide order, it failed exactly twice, at 16 and 40,960. Result: `build/logs/ConstructionBeforeFix-8DBF111A-CBBD-41DB-B158-652A8D700EFB.xcresult`; log: `/tmp/notehush-issue46-construction-before.log`. Base is the main commit above with only the optional style argument and new regression added.

Earlier experiments constructed an empty `EditorTab`, changed its style afterward and performed a second programmatic text assignment. That differs from initial restoration, including having delegates/observers installed. It reproduced layout even with the proposed initialization change. The final test configures the style before the real snapshot restoration and keeps the same fixtures and zero-layout, byte/selection and presentation assertions. The earlier failures remain in `LayoutBeforeFix-7DD243A6-4616-4569-ADC0-F0C4ECF3164A.xcresult`, `LayoutAfterFix-E6DBB608-8430-4A42-830B-81499A0D9C6F.xcresult` and the `LayoutState-*` diagnostic bundle. No arbitrary post-construction text mutation is claimed to avoid layout.

Temporary probe sources/binaries are retained under this issue worktree's ignored `build/diagnostics/`; logs are `/tmp/notehush-issue46-layout-probe.log`, `-layout-trigger.log`, `-long-paragraph.log`, `-empty-first.log` and `-state.log`. The first probe compile used an obsolete Swift type spelling and failed; its corrected build used `NSScroller.Style`. Native diagnostic warnings and all failed results remain retained. None of those probes ship.

## Implementation and checks

Initialization disables `autohidesScrollers`; `restoreScroll()` enables it before measuring the viewport or configuring wrapping. This avoids hidden initial layout while allowing AppKit to decide scrollbar visibility when the editor is presented. The existing text assignment, typography, selection, undo, marked-text handling, recovery I/O and four sandbox entitlements remain unchanged.

Apple documents [the system's preferred scrollbar style](https://developer.apple.com/documentation/appkit/nsscroller/preferredscrollerstyle) and [the scroll view's instance style](https://developer.apple.com/documentation/appkit/nsscrollview/scrollerstyle). The installed SDK headers confirm both are public API and that the preferred style can change with preferences/pointing devices. [NSLayoutManager](https://developer.apple.com/documentation/appkit/nslayoutmanager) supports noncontiguous layout; enabling it alone does not prevent this observed native scrollbar-triggered work. References and SDK declarations checked 2026-09-07.

The new regression covers both styles and both fixtures before/after font and wrap changes, exact UTF-8, a saved UTF-16 caret, initial 14-point font sizing and native vertical/horizontal scrollbars with auto-hiding enabled after presentation. A native Arabic font fallback is permitted; the test does not force a particular fallback face. All original editor/recovery assertions and test time allowances remain intact.

The candidate passed all **34 AppKit tests**, zero failures, in 18.986 seconds. The new regression passed in 1.841 seconds. This includes the original hidden-editor and 5 MiB workspace/caret/viewport restart tests plus existing marked-text, undo, typography and file/recovery cases. Build-for-testing, strict Swift formatting, diff checks and exact product-entitlement signature verification before/after the native invocation passed. Evidence: `build/logs/ConstructionAfterFix-97A136E3-50C2-4A9F-BCDD-A04B465B6586.xcresult`, `/tmp/notehush-issue46-construction-fixed-build.log` and `/tmp/notehush-issue46-construction-after.log`. The checkout was based on the main commit above with the candidate source/test changes uncommitted; this is local correctness evidence, not a final-head CI or latency result.

Full native validation and optimized launch/interaction measurements after integration with #43 remain required. Reference M1/8 GiB hardware, macOS 14/Intel runtime, real IMEs, accessibility and distribution signing remain unverified. This correction does not establish App Store readiness or close the broader performance gates.
