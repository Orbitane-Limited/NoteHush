# Generated long-paragraph TextKit time profile

Issue [#75](https://github.com/Orbitane-Limited/NoteHush/issues/75) remains unresolved. This bounded profile examines only the generated-data `NativeSoftBreakDelegateProbe` already retained on this validation branch. It does not profile NoteHush or any unrelated process and does not change application code.

## Workload and environment

The probe assigned exactly 10,485,760 generated UTF-8 bytes: a 16-byte ASCII header followed by one unbroken Arabic/emoji paragraph. It then requested the first viewport from a TextKit 2 `NSTextView`. The profile began about one second after launch, after the probe logged `stage=assigned`, and sampled the exact child PID for four seconds at a 1 ms interval. The probe was then terminated by the harness; it had not returned from the synchronous layout request.

Environment: arm64 macOS 26.6.2, Xcode 26.6 (17F113). The hardware model was unavailable to the restricted shell. The generated-data process reported 1.5 GiB current and peak physical footprint during this interval. This is a short diagnostic observation, not a product memory benchmark.

## Finding

The sample contained 3,391 stack samples. The main-thread layout stack accounted for 3,311 and remained inside `NSTextLayoutManager.ensureLayoutForBounds` → `NSTextLayoutFragment._layout` → `NSCoreTypesetter` → `CTTypesetterCreateWithAttributedStringAndOptions` → Core Text typesetter initialization and glyph shaping. The most common sampled work was `TTypesetter::FinishEncoding` / `TShapingEngine::ShapeGlyphs`; bidirectional reordering and font glyph-advance lookup also appeared below it.

The delegate's `shouldBreakLineBefore` callback had not fired when this profile was taken. The earlier bounded run of the same probe records no callback before its 12-second limit. This places the long delay before the proposed line-break callback and confirms that the native TextKit request is spending the sampled time constructing and shaping the paragraph typesetter. It does not establish a safe way to interrupt or partition that work while preserving paragraph-level Unicode behavior.

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

The raw sample contains system stack and process metadata only; the source document was generated. No user file was read. This profile supports the TextKit/Core Text shaping diagnosis but is not an unprofiled performance result, an app-level acceptance pass, or a product correction. All #75 acceptance criteria remain open.
