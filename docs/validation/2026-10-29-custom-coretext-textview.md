# Custom Core Text fragments in a native text view

**Date:** 2026-10-29  
**Purpose:** determine whether a delegate-provided Core Text fragment can keep the existing TextKit 2 `NSTextView` responsive on the long-paragraph fixture. This is a diagnostic only; it does not change NoteHush's editor.

The reproducer in [`reproducers/CustomCoreTextFragmentProbe.swift`](reproducers/CustomCoreTextFragmentProbe.swift) installs an `NSTextLayoutManagerDelegate` that builds `NSTextLineFragment` instances around Core Text lines and returns an `NSTextLayoutFragment`. It attaches the manager to a native `NSTextView`, assigns the generated mixed-script fixture, and requests layout for the 858-by-600 viewport.

On this Mac, the 16 KiB fixture completed viewport layout in 0.0287 seconds. The 10 MiB fixture (5,242,888 UTF-16 units) did not complete within 12 seconds. A separately instrumented six-second observation confirmed that the delegate received the 5,242,872-unit body paragraph, but its `CTFramesetterCreateFrame` call had not returned before the observation ended. The process was externally time-bounded; no editor source or user data was involved.

A standalone TextKit 2 layout-manager probe had previously completed custom-fragment layout for the same generated 10 MiB fixture in 2.4266 seconds. That result does not transfer to an `NSTextView`: the native view integration remains slow. The custom-fragment route is therefore not a demonstrated editor correction and must not be adopted on this evidence.

To reproduce, compile with the installed Xcode toolchain and a temporary module cache, then run each fixture size under a fixed timeout:

```sh
xcrun swiftc -parse-as-library -module-cache-path /private/tmp/notehush-clang-cache \
  docs/validation/reproducers/CustomCoreTextFragmentProbe.swift \
  -framework AppKit -framework CoreText -framework CryptoKit \
  -o /private/tmp/CustomCoreTextFragmentProbe
timeout 12 /private/tmp/CustomCoreTextFragmentProbe 16384
timeout 12 /private/tmp/CustomCoreTextFragmentProbe 10485760
```

The executable accepts a byte count. Preserve timeout output and process status. The source prints only fixture size, digest, numeric ranges/timings, and line counts; it does not print fixture text.

No text limit, encoding, paragraph structure, assertion, or timeout was changed. No shipping code changed. Issue #75 remains open pending a tested correction and the unchanged full native performance protocol.
