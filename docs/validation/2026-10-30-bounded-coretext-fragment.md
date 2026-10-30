# Bounded Core Text lines in a native TextKit fragment

Issue #75 remains unresolved. This generated-data probe uses the standard
`NSTextContentStorage` and its native document locations, but supplies a custom
`NSTextLayoutFragment` containing a bounded Core Text line group for the first
portion of one long paragraph. It does not change application source or file
behavior.

## Results

The source text is generated in memory. The 10 MiB case is a 16-byte header
followed by the same repeated Arabic/emoji paragraph used in the retained issue
probes. For the 16 KiB fixture, the first 4,048 UTF-16 units of the body
produced 44 lines whose starts, lengths, and widths exactly matched the native
TextKit control for that range.

For 10 MiB, the initial viewport request completed in 88.5 ms in this single
headless run. It returned a layout-available fragment for UTF-16 range 16–4,064
with 44 lines. The generated bitmap contained 230,304 nonwhite pixels, and
visual inspection showed rendered glyphs. These observations cover only that
first partial fragment; they are not a launch or input-latency acceptance run.

The same manager then requested ranges around body offsets 5,000, 2,621,436,
and 5,238,776. The probe invalidated each target range and retried after
invalidating the paragraph range. TextKit did not ask the delegate for another
fragment, and `textLayoutFragment(for:)` returned nil for each target. Thus the
custom fragment can render an initial portion, but this implementation cannot
provide later paragraph content for scrolling. It is not a usable editor fix.

## Reproduction and provenance

```sh
xcrun swiftc -O -parse-as-library -target arm64-apple-macosx14.0 -swift-version 6 \
  -warnings-as-errors -module-cache-path /private/tmp/notehush-modulecache \
  docs/validation/reproducers/BoundedCoreTextFragmentProbe.swift \
  -framework AppKit -framework CoreText -o /private/tmp/BoundedCoreTextFragmentProbe
/private/tmp/BoundedCoreTextFragmentProbe 16384
/private/tmp/BoundedCoreTextFragmentProbe 10485760
```

The 16 KiB run exited 0 and reported `nativeRows=44 partialRows=44`, exact
starts/lengths and widths. The 10 MiB run exited 0 as a diagnostic harness, but
its later-offset requests returned no fragment. The run outputs and generated
bitmap are retained under the ignored local `build/logs/BoundedCoreTextFragment-20261030/`
directory. SHA-256 values:

| Artifact | SHA-256 |
| --- | --- |
| Source | `fa35154fd7580ad05774bd0041ccd6d9656d069172355cfabdfd1955f850da62` |
| Optimized binary | `0078eba2e56a3af92b3fc92de1b220b76f8ee0da238f3e129ff451428077fc29` |
| 16 KiB output | `d61b9b64d5630974cf4c07e8bc792e13d5e7216625f9f3cb6a4bff62c7d69fef` |
| 10 MiB output | `10d57d5332e5770c72ed75ee6b46efc1a76815a8d39c71f6735e4fd9cc74f2c9` |
| Generated first-viewport bitmap | `c21c1b7bc92488117a945468b9279b0850cd028f5b447cbaf8c08311c77ae550` |

The probe preserves the generated source bytes and does not test arbitrary
Unicode, mixed-script range equivalence, user input, IME, selection, Undo,
accessibility, recovery, or real scroll interaction. It leaves the native
TextKit storage intact but does not establish complete paragraph layout. No
limits, deadlines, source text, or acceptance assertions were relaxed.
