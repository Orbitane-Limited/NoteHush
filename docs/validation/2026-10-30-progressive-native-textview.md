# Progressive native-location TextView integration control

Issue #75 remains unresolved. This generated-data probe combines line-aligned
incremental chunk planning with a subclass of `NSTextContentStorage` that
creates locations through its native superclass implementation. It checks
whether this avoids the custom-location mismatch while attaching to an editable
`NSTextView`.

## Workload and result

The probe generates exactly 10,485,760 UTF-8 bytes: a 16-byte header followed
by one Arabic/emoji paragraph. It reads no user document. Swift 6 compilation
with warnings treated as errors succeeded for the macOS 14 deployment target.

The native `NSTextContentStorage` subclass attached to `NSTextView`; the view
became first responder and its complete backing string remained exact. This
demonstrates that using native storage locations avoids the earlier immediate
location-type exception for this attachment path.

The 65,536-unit Core Text planning window reached the first viewport with one
65,534-unit planned chunk. Initial native TextView layout took **3.346 seconds**,
which misses the existing one-second opening target. Planning through the
middle of the source took **722.6 ms**. Then requesting native layout from the
document start through the middle range took about **98.7 seconds**. The
returned middle fragment had `frameY=0.0` after that prefix request; the test
therefore did not establish a usable scroll position. Forty-one planned chunks
covered 2,686,254 UTF-16 units at that point.

This route can attach an editable native view, but it fails initial latency and
does not produce correct middle-scroll geometry. It is not an app correction.
No file limit, text, deadline, or acceptance requirement changed.

## Reproduction

```sh
xcrun swiftc -O -parse-as-library -target arm64-apple-macosx14.0 -swift-version 6 \
  -warnings-as-errors -module-cache-path /private/tmp/NativeProgressiveTextViewModuleCache \
  docs/validation/reproducers/NativeProgressiveTextViewProbe.swift \
  -framework AppKit -framework CoreText -o /private/tmp/NativeProgressiveTextViewProbe
/private/tmp/NativeProgressiveTextViewProbe
```

The exact observed output was:

```text
initial textview=attached firstResponder=true planned=65534 layoutMs=3345.6165833049454 chunks=1 emitted=4 textExact=true
middle planned=2686254 planMs=722.6287499652244 prefixLayoutMs=99442.07954168087 fragment=true frameY=0.0 chunks=41 emitted=46
```

The prefix total includes the 722.6 ms planning interval; subtraction gives
approximately 98.7 seconds for the layout request. Source SHA-256:
`8a1dcb47d1ef7524adce06caa6268368cd37eff54d3d197ee69ff10001af2a2b`.
Binary SHA-256:
`85c47d21e8b3e6a70b54f988e2bcae3aca14d3cf0c8050b44000a9533a300f74`.
