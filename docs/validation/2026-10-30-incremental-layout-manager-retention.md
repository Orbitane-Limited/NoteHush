# Retaining the custom TextKit layout manager after edits

Issue #75 remains unresolved. This generated-data prototype changes only the
isolated `NSTextInputClient` diagnostic: after an edit it keeps the same
`NSTextLayoutManager` attached to the custom `NSTextContentManager` instead of
removing and recreating the layout manager. No app source or supported-file
behavior changed.

## Fixture and observation

The probe generates 10,485,760 UTF-8 bytes in memory: a 16-byte header and a
repeated Arabic/emoji body. It reads no user files and logs no document text.
The prototype completed its exact-text checks for initial insertion, repeated
synthetic key events, marked-text update and commit, middle insertion, append,
cross-chunk replacement, empty draft, and its separate TextKit content-manager
edit transaction.

The first post-edit viewport request then terminated with status 134 while
`NSTextLayoutManager.ensureLayout(for:)` was laying out the first viewport. The
exception was:

```text
-[NSCountableTextLocation compare:] receiving unmatching type <InputProbeLocation>
```

The stack passes through TextKit's text-layout-fragment storage and the
prototype's `enumerateTextElements` callback. No viewport coverage or rendered
bitmap was produced. Therefore the retained-manager approach does not meet the
rendering/scrolling requirement and is rejected as an app correction. The
failure does not establish whether the framework's retained internal location
or this prototype's location contract is the root cause.

## Reproduction

```sh
xcrun swiftc -O -parse-as-library -target arm64-apple-macosx14.0 -swift-version 6 \
  -module-cache-path /private/tmp/notehush-issue75-module-cache \
  docs/validation/reproducers/IncrementalChunkManagerRetainProbe.swift \
  -framework AppKit -framework CoreText -o /private/tmp/IncrementalChunkManagerRetainProbe
/private/tmp/IncrementalChunkManagerRetainProbe
```

Expected result: the process fails during first viewport layout with the
`NSCountableTextLocation` type-mismatch exception above. The original text,
input sizes, and test bounds are not changed. The log contains only generated fixture diagnostics and the AppKit
exception/backtrace. Its SHA-256 is `567c2746d637a92c44a7fd28cd45ffdc63144c8b45812ec810616df3997089f7`.

## Environment and limits

macOS 26.6.2 (25G83), Xcode 26.6 (17F113), Swift 6.3.3, arm64. This is an
isolated diagnostic, not a product editor test. It does not implement
production selection navigation, undo, accessibility, recovery, files, tabs,
Find, print, or physical IME behavior. It provides no successful latency,
rendering, or performance result. No timeout, fixture size, paragraph breaks,
file limit, or assertion was relaxed.


Source SHA-256: `e4b7576a259975d62dd203c1d9fbf320db8d3ff75abb2e971350d728b91e1e02`.
Binary SHA-256: `c17625f5003138c0e242564e56138ed31eaeb2e9f6f51f60f837c4df834b491e`.
