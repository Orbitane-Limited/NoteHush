# Custom text input client probe

Issue #75 remains unresolved. This generated-data-only probe checks whether the fast custom range renderer can at least compile a Swift 6 `NSTextInputClient` surface and preserve basic UTF-16 edit/composition ranges. It changes no application source and reads no user document.

## Result

`CustomTextInputClientProbe.swift` compiles with Swift 6.3.3 against AppKit on the local arm64 macOS 26.6.2 host. The view uses a `@preconcurrency NSTextInputClient` conformance because AppKit protocol requirements are imported as nonisolated while `NSView` is main-actor isolated. `keyDown(with:)` routes through the view's `NSTextInputContext.handleEvent(_:)`, then falls back to `interpretKeyEvents(_:)` when the text system declines the event.

The executable's generated checks passed for:

- Inserting `A👩🏽‍💻B` and measuring the caret in UTF-16 units.
- Replacing the seven-unit emoji selection with marked Japanese text `かな`.
- Committing the composition as `仮名` and checking the final caret and text.

Command: `swiftc -swift-version 6 -O -module-cache-path /private/tmp/NoteHushInputModuleCache -framework AppKit docs/validation/reproducers/CustomTextInputClientProbe.swift -o /private/tmp/NoteHushCustomTextInputClientProbe && /private/tmp/NoteHushCustomTextInputClientProbe`

The run printed `Generated NSTextInputClient range/composition probe passed`. `swift-format lint --strict` and `git diff --check` passed.

## Limits

This is a callback/range harness, not a functioning editor. It does not dispatch a real keyboard event through a visible window or exercise a real Japanese/Chinese IME. It has no renderer, hit testing, caret/selection geometry, clipboard, editing commands, undo, accessibility text roles, find/replace, printing, recovery, or edit-aware viewport index. In particular, `firstRect(forCharacterRange:actualRange:)` currently returns the view bounds and `characterIndex(for:)` returns `NSNotFound`; those are placeholders, not acceptable product behavior.

The API surface is implementable, but replacing `NSTextView` would still require an independent text editor and broad native-input/accessibility regression coverage. The probe therefore does not justify changing the shipping editor or close #75. Apple's [NSTextInputClient](https://developer.apple.com/documentation/appkit/nstextinputclient) defines the text-view callback contract; [NSTextInputContext](https://developer.apple.com/documentation/appkit/nstextinputcontext) routes key events to that client.

Source SHA-256: `c4d106c4cc656057d0f381757cea3df9487ca3c665918cb89cfdf34ef41ae812`.
Binary SHA-256: `55937bca6c318bfeb93468e20014822af9ea7987676a17d3d41b99a3e473b45f`.
