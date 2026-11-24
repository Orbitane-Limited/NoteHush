# Default-storage suspicious-content layout experiment

**Date:** 2026-10-29  
**Purpose:** close the gap in the earlier defensive-layout experiment, which used a custom `NSTextContentManager`, by running the same setting against a standard TextKit 2 `NSTextView` and its default `NSTextContentStorage`.

The reproducer in [`reproducers/DefaultStorageSuspiciousProbe.swift`](reproducers/DefaultStorageSuspiciousProbe.swift) generates the same 10 MiB Arabic/emoji one-paragraph fixture, assigns it to an unmodified native text view, and requests layout for the first 858-by-600-point viewport. Each setting was run in a fresh process with a 12-second subprocess deadline. Text was assigned in about 0.01 seconds in both cases. No user data, app process, or product source was used.

| `limitsLayoutForSuspiciousContents` | Result |
| --- | --- |
| `false` | Viewport layout did not return within 12 seconds. The harness terminated its own process. |
| `true` | The process exited with code `-5` (signal 5) before reporting viewport layout. |

Both cases used the same generated UTF-8 SHA-256 `e4e0a3ac39ad74b9b5d4b0b6c85e46ba7d1ea2f6c7ddd4c287f0e1e07effdd63` and assigned 5,242,888 UTF-16 units. The setting does not resolve the stall on the standard storage path and is unsafe as a workaround. This agrees with the earlier custom-manager experiment and Apple's warning that this defensive mode may yield unexpected layout for long paragraphs.

Reproduce from the repository root on the same Xcode toolchain:

```sh
xcrun swiftc -parse-as-library \
  -module-cache-path /private/tmp/NoteHushDefaultStorageProbeModuleCache \
  docs/validation/reproducers/DefaultStorageSuspiciousProbe.swift \
  -framework AppKit -framework CryptoKit \
  -o /private/tmp/NoteHushDefaultStorageSuspiciousProbe
```

Run `false` and `true` as the first argument with `10485760` as the second argument. Apply an external 12-second process bound to each run and retain both exit statuses. The diagnostic changed no application behavior or acceptance criteria. Issue #75 remains unresolved.
