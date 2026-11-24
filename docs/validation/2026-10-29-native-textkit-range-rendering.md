# Native TextKit targeted range rendering

Issue #75 remains unresolved. This generated-data experiment checks whether a native TextKit 2 layout fragment can draw text at chosen points in a pathological document without laying out every preceding line. It uses only a generated 10 MiB Arabic/emoji fixture, creates no window, reads no user document, and changes no application source.

## Result

On an arm64 MacBook Pro (M4 Pro), macOS 26.6.2, Xcode 26.6 / Swift 6.3.3, the probe created a 5,242,888-UTF-16-unit fixture (`123456789012345\n` followed by repeated `خط📝`) and divided it into native-shaped `NSTextParagraph` elements aligned to the same TextKit line boundaries. It planned 1,296 elements and 56,989 lines in 13.799 seconds. The probe then requested a 1,024-unit range at each position, drew the returned fragment(s) into an 868 × 500 offscreen bitmap, and compared line starts, lengths and typographic-width bit patterns with the planner.

| Position | UTF-16 offset | Fragments | Lines checked | Exact geometry | Non-white bitmap pixels | Request + draw |
| --- | ---: | ---: | ---: | --- | ---: | ---: |
| Start | 0 | 1 | 45 | Yes | 194,279 | 55.96 ms |
| Middle | 2,621,444 | 1 | 44 | Yes | 206,849 | 40.09 ms |
| End | 5,241,864 | 2 | 52 | Yes | 206,849 | 32.58 ms |

The drawing check translates each fragment from document coordinates into the offscreen viewport before clipping. Pixel counts show that the generated fixture produced glyph pixels at all three requested positions; they are not a pixel-for-pixel comparison with `NSTextView`, a visible-frame measurement, or proof of complete editor behavior.

## Limits

Targeted TextKit layout and drawing are bounded in this probe, but the full line-planning pass still takes 13.8 seconds. Background indexing, immediate first-frame editing, insertion/deletion invalidation, caret and selection movement, mouse hit testing, undo, IME, accessibility, find, recovery, printing, scrolling in an attached view, and file lifecycle were not tested. The manager and drawing surface are diagnostic prototypes, not a replacement editor.

This result supports further work on a lazy native viewport, but it does not justify integrating the prototype or closing #75. A correction still needs to preserve the existing editor's native editing and recovery behavior and pass the unchanged app-level responsiveness checks.

## Reproduction

```sh
swiftc -parse-as-library -target arm64-apple-macosx14.0 -swift-version 6 -O \
  docs/validation/reproducers/NativeTextKitChunkedViewportProbe.swift \
  -framework AppKit -o /private/tmp/NoteHushNativeTextKitChunkedViewportProbe
python3 -c 'import subprocess; subprocess.run(["/private/tmp/NoteHushNativeTextKitChunkedViewportProbe"], timeout=45, check=True)'
```

The compiled source used a module cache under the repository build directory. Source SHA-256: `94e1ade80e2fd385aa3a96ea523d343197dc083a1a7eccfc637aa6c648e59571`. Binary SHA-256: `e8a62bb3059a16e871e7baa9a60207f97e9b88d65c3efc011cdafd609e4bae56`.
