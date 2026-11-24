# Core Text and TextView line geometry calibration

Issue #75 remains unresolved. This control corrects the width mismatch in the earlier `CoreTextNativeGeometryControl.swift` comparison and checks line UTF-16 ranges against a native `NSTextView` using TextKit 2.

## Method

A hidden, headless `NSTextView(usingTextLayoutManager: true)` uses the app's 900-point view width, 16-point horizontal text inset and 868-point text-container width. The container's default 5-point line-fragment padding leaves 858 points for line layout. Core Text receives that same 858-point width. Both engines receive the same unmodified attributed string, monospaced system font, natural paragraph direction and generated case. The oracle compares each line's UTF-16 start and length; it does not compare pixels, glyph positions, interaction or performance.

The source is [`CoreTextTextViewGeometryCalibration.swift`](reproducers/CoreTextTextViewGeometryCalibration.swift), SHA-256 `44cd780f38f3f00033151371861a3804461e5482a4b655d59fbada6a6b9071be`. It creates generated input in memory and emits only case labels, sizes, line counts, hashes and the first two numeric ranges. It opens no document, sends no input, and accesses no user text.

## Result

Run on the local arm64 MacBook Pro 16,8 (M4 Pro, macOS 26.6.2, Xcode 26.6 / Swift 6.3.3) with Swift 6 optimized compilation and a macOS 14 deployment target:

| Generated case | UTF-8 bytes | TextView lines | Core Text lines | Exact UTF-16 ranges |
| --- | ---: | ---: | ---: | --- |
| Repeated Arabic and emoji | 16,000 | 87 | 87 | Yes |
| Latin, Arabic, digits, Hebrew and emoji | 17,000 | 112 | 112 | Yes |
| Combining Latin, Arabic, Hebrew and emoji | 28,500 | 125 | 150 | No |
| Parentheses, Arabic, Hebrew, digits and emoji | 25,000 | 175 | 175 | Yes |

For the differing combining-script case, TextView starts with line ranges `(0, 124)`, `(124, 124)` while Core Text starts `(0, 104)`, `(104, 105)`. An additional diagnostic assigned `CTFontCreateForString` fallback names to composed-character spans. It retained the 125/150-line disagreement; Core Text's private `.AppleColorEmojiUI` name could not be instantiated by `NSFont(name:size:)`, so that experiment is not evidence of equivalent fallback rendering.

## Reproduction

```sh
swiftc -parse-as-library -target arm64-apple-macosx14.0 -swift-version 6 -O \
  -module-cache-path /private/tmp/NoteHushGeometryModuleCache \
  docs/validation/reproducers/CoreTextTextViewGeometryCalibration.swift \
  -framework AppKit -framework CoreText -framework CryptoKit \
  -o /private/tmp/NoteHushGeometryCalibration
/private/tmp/NoteHushGeometryCalibration
```

The control shows that matching available width corrects three generated cases, but it does not establish general equivalence. The remaining mismatch disproves using this Core Text index as a general substitute for TextKit line mapping. It changes no app behavior, text, limits, or acceptance criteria, and does not resolve the 10 MiB issue.
