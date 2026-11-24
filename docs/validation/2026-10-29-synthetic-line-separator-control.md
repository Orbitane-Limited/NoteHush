# Synthetic soft-wrap separator control

Issue #75 remains unresolved. This generated-data control tests whether a native TextKit 2 paragraph can be divided at its own soft-wrap boundaries by inserting U+2028 LINE SEPARATOR characters into a presentation copy. It does not change NoteHush source or user files.

## Small geometry controls

The control measured each complete paragraph with native TextKit 2, inserted a candidate separator after every measured soft line, then measured the transformed presentation and mapped its line ranges back to source UTF-16 offsets.

On four generated fixtures, U+2028 preserved every line start, source length, and typographic-width bit pattern. A literal LF preserved those values for Arabic plus emoji but changed line widths in the mixed Latin/Arabic/Hebrew, combining-mark, and punctuation fixtures. These observations establish small-fixture geometry only; they do not establish editing or large-document performance.

| Generated fixture | UTF-16 units | Lines | LF geometry | U+2028 geometry |
| --- | ---: | ---: | --- | --- |
| Arabic + emoji | 8,000 | 87 | Exact | Exact |
| Latin, Arabic, digits, Hebrew, emoji | 11,000 | 116 | Width mismatch | Exact |
| Combining Latin, Arabic, Hebrew, emoji | 15,500 | 132 | Width mismatch | Exact |
| Arabic/Hebrew punctuation and parentheses | 17,000 | 177 | Width mismatch | Exact |

## 10 MiB control

The generated input was 10,485,760 UTF-8 bytes and 5,242,888 UTF-16 units. The bounded native planner found 56,989 line boundaries in 1,296 windows in 13.497 seconds. The experiment inserted 56,988 U+2028 characters into a presentation copy and requested full-document layout and fragment enumeration through `NSTextContentStorage` and `NSTextLayoutManager`.

That operation returned no result during the following 90 seconds. I interrupted the generated-only process; it did not access a NoteHush workspace or user document. The probe did not reach editing, selection, copy/search, undo, recovery, or lifecycle checks. Its output is a bounded timeout, not a successful performance sample.

## Result and limits

U+2028 is not a viable correction on this evidence: the transformed 10 MiB document did not complete full layout within the unchanged ten-second target, and inserting separator characters would also require a complete source-offset and text-operation mapping layer. No application behavior, supported file limits, or acceptance criteria changed. Issue #75 stays open.

The small control source is [`SoftBreakLayoutProbe.swift`](reproducers/SoftBreakLayoutProbe.swift); the large control is [`SoftBreakLargeProbe.swift`](reproducers/SoftBreakLargeProbe.swift). Both are generated-data TextKit diagnostics, not editor tests. The formatted archived source hashes are `b6d02cb01b0e1f1722f7443fd059becdcb66bbcd3f0e6c729c5f501a62ad068d` and `35a02a49001e68855e8254f47177f6a4a70a0126743160452ad0c6d12a603482`. The large run compiled the pre-format source (`1c7ba03ecab3de978ec8eea39f52c331dd0e5f2cef4b034bf4db73f021b455ca`, binary SHA-256 `0adacb7b3234b4817b596663f46c2235de6e05d4d9f0c8f405df1645246cd014`); formatting changed whitespace only. The run used Swift 6 and a macOS 14 deployment target on the local arm64 macOS 26.6.2 host.
