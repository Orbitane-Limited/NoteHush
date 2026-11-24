# Full-length paragraph direction control

Issue #75 remains unresolved. This generated-data control asks whether setting an explicit native paragraph base direction through the existing `NSTextContentStorageDelegate` can make the first `NSTextView` viewport responsive for the exact 10 MiB Arabic/emoji paragraph.

## Result

The arm64 probe ran on macOS 26.6.2 with Xcode 26.6 / Swift 6.3.3. It assigned a 10,485,760-byte generated buffer containing a 16-byte header and 5,242,872 UTF-16 units in its body paragraph. Assignment took 4.367 seconds. The delegate's public `CFAttributedStringGetStatisticalWritingDirections` call returned for both paragraphs and supplied explicit left-to-right / right-to-left paragraph styles on presentation copies. The subsequent 2,048-unit `NSTextView` TextKit 2 viewport layout did not return before the 30-second process bound. The exact console stage output is in [`LongResolvedDirectionTextViewProbe.log`](reproducers/LongResolvedDirectionTextViewProbe.log); the generated probe process was terminated by the external bound.

The direction resolver therefore does not remove the measured viewport stall for this fixture. This negative result does not identify the underlying hot path. It also does not justify raising the shipping presenter's 1 MiB bound: the probe did not complete layout, and it required additional per-unit direction arrays and a full attributed copy.

No application source, fixture limits, timeouts, file contents or acceptance criteria changed. No user documents or app process were involved. This is not an application test or a passing performance sample.

## Reproduction

```sh
swiftc -parse-as-library -target arm64-apple-macosx14.0 -swift-version 6 -O \
  docs/validation/reproducers/LongResolvedDirectionTextViewProbe.swift \
  -framework AppKit -framework CoreFoundation \
  -o /private/tmp/LongResolvedDirectionTextViewProbe
python3 -c 'import subprocess; subprocess.run(["/private/tmp/LongResolvedDirectionTextViewProbe"], timeout=30, check=True)'
```

Source SHA-256: `6ef2f6ad99a50b302c60bfbcd8c41033822f036962bed63a162e11a47ada1ae7`. Binary SHA-256: `82d980abad2df6b321cbd2504e4f58c7950cc916d9de76e0dc922f8ca0190e68`.
