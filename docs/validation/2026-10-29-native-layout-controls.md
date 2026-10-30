# Native large-paragraph layout controls

Issue #75 remains unresolved. These generated-data controls check two possible configuration changes: limiting TextKit 1 work to the visible glyph range with background layout enabled, and using the proportional system font instead of the app's monospaced font. Neither is a product fix.

## TextKit 1 visible-range control

The headless probe source is [`LegacyVisibleViewportTextKit1Probe.swift`](reproducers/LegacyVisibleViewportTextKit1Probe.swift), SHA-256 `b6fae9d323ab6dd25ea9dc7fd4d9334be0c8812601c5730af76fce64b17ea436`. It uses the exact generated 10,485,760-byte fixture from #75 (SHA-256 `e4e0a3ac39ad74b9b5d4b0b6c85e46ba7d1ea2f6c7ddd4c287f0e1e07effdd63`) in a native `NSTextView(usingTextLayoutManager: false)`. It uses the app's 14-point font, 868-point container and default 5-point fragment padding, with `allowsNonContiguousLayout` and `backgroundLayoutEnabled` enabled. It asks `NSLayoutManager` for the glyph range in the visible rectangle, then calls `ensureLayout(forGlyphRange:)` for that range.

| Stage | Observation |
| --- | ---: |
| Assign full fixture | 3.790 s |
| Query visible glyph range | 0.000006 s; range `{0, 2304}` |
| Ensure visible-range layout | Did not return before the 10.5-second process bound |

The quick range query does not prove those glyphs are ready to display. Synchronous layout of only the returned visible range still did not meet the issue's unchanged bound. The formatted committed source was recompiled and repeated: assignment took 3.774 seconds, the same `{0, 2304}` glyph range returned in 0.000006 seconds, and `ensureLayout` again timed out. The external timeout killed the isolated generated-data process; it did not modify the app or any user file.

## TextKit 2 proportional-font control

The headless probe source is [`TextKit2SystemFontLongParagraphProbe.swift`](reproducers/TextKit2SystemFontLongParagraphProbe.swift), SHA-256 `7031e9dc06352fe3ee91e4fc7d5605c2a7c78cf1fdd7e6a4e3d6047553fb9df3`. It uses `NSTextView(usingTextLayoutManager: true)` and the same exact 10 MiB fixture, width and paragraph style, but uses `NSFont.systemFont(ofSize: 14)` rather than the app's monospaced system font.

On the same arm64 MacBook Pro 16,8 (M4 Pro, macOS 26.6.2, Xcode 26.6 / Swift 6.3.3), assigning the attributed fixture took 0.0115 seconds and preserved its 5,242,888 UTF-16 units and expected SHA-256. Complete `NSTextLayoutManager.ensureLayout(for:)` did not return within the same 10.5-second bound. The formatted committed source was recompiled and repeated: assignment took 0.0115 seconds, then full layout again timed out. The font change therefore does not resolve whole-paragraph shaping; no change to the product's default font is justified by this control.

## Reproduction

On an awake development Mac with Xcode 26.6, compile each source with Swift 6 and a macOS 14 deployment target, then run each process with an external 10.5-second timeout:

```sh
swiftc -parse-as-library -target arm64-apple-macosx14.0 -swift-version 6 -O \
  docs/validation/reproducers/LegacyVisibleViewportTextKit1Probe.swift \
  -framework AppKit -framework CryptoKit -o /private/tmp/LegacyVisibleViewportTextKit1Probe
python3 -c 'import subprocess; subprocess.run(["/private/tmp/LegacyVisibleViewportTextKit1Probe"], timeout=10.5, check=True)'

swiftc -parse-as-library -target arm64-apple-macosx14.0 -swift-version 6 -O \
  docs/validation/reproducers/TextKit2SystemFontLongParagraphProbe.swift \
  -framework AppKit -framework CryptoKit -o /private/tmp/TextKit2SystemFontLongParagraphProbe
python3 -c 'import subprocess; subprocess.run(["/private/tmp/TextKit2SystemFontLongParagraphProbe"], timeout=10.5, check=True)'
```

The system-font source records the exact stage output before full layout begins. The TextKit 1 source flushes stage output so its visible-range result remains observable when the bounded host kills the stalled process. These are one-off diagnostic observations, not performance percentiles, complete editor tests, or proof of user-visible rendering.

Apple describes `backgroundLayoutEnabled` as scheduling glyph generation/layout when the app's run loop is idle, and cautions that a layout-manager object graph must not be accessed concurrently across threads. See [NSLayoutManager](https://developer.apple.com/documentation/appkit/nslayoutmanager). Neither property changes the synchronous behavior observed when the probe explicitly requests visible-range layout.

## Shared AppKit typesetter control

[`SharedTypesetterLongParagraphProbe.swift`](reproducers/SharedTypesetterLongParagraphProbe.swift) repeats the TextKit 1 visible-range fixture and layout request in two isolated processes. One keeps the layout manager's default typesetter; the other assigns `NSATSTypesetter.shared`. Both report the concrete class as `NSATSTypesetter`, assign the exact fixture in approximately 3.8 seconds, return visible glyph range `{0, 2304}` in under 0.00001 seconds, and then exceed the 10.5-second process bound in `ensureLayout(forGlyphRange:)`. This is not a faster native typesetter route. No product behavior was changed.

```sh
swiftc -parse-as-library -target arm64-apple-macosx14.0 -swift-version 6 -O \
  docs/validation/reproducers/SharedTypesetterLongParagraphProbe.swift \
  -framework AppKit -framework CryptoKit -o /private/tmp/SharedTypesetterLongParagraphProbe
python3 -c 'import subprocess; subprocess.run(["/private/tmp/SharedTypesetterLongParagraphProbe"], timeout=10.5, check=True)'
python3 -c 'import subprocess; subprocess.run(["/private/tmp/SharedTypesetterLongParagraphProbe", "--shared-typesetter"], timeout=10.5, check=True)'
```
