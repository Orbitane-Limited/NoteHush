# Native literal-text input policy

Issue #64. Base main `db6e306dab459d45ecb9e723a55712f8354f5069`.

The editor already disabled automatic quote/dash/text replacement and spelling correction, but inherited other native text-generation defaults. The installed SDK documents automatic Touch Bar completion as enabled by default, exposes per-view inline prediction from macOS 14, and exposes math completion and Writing Tools from macOS 15. Those defaults vary independently of NoteHush’s optional spelling preference.

The editor now explicitly disables inline and automatic Touch Bar completion, and under a macOS 15 availability guard disables math completion and sets Writing Tools behavior to `none`. Scope is the editable note view. Global input preferences, spell-check selection, recovery and file bytes are not modified by this configuration. Existing per-tab Undo and marked-text/native input checks remain required.

Apple documents [inline prediction](https://developer.apple.com/documentation/appkit/nstextview/inlinepredictiontype), [Writing Tools behavior](https://developer.apple.com/documentation/appkit/nswritingtoolsbehavior) and [the opt-out](https://developer.apple.com/documentation/appkit/nswritingtoolsbehavior/none). The local `NSTextView.h` availability declarations were inspected on 2026-09-08 UTC.

This is an explicit configuration of the existing v1 literal-text/no-AI scope. It is not evidence that the app transmitted notes, a diagnosis of #29’s past input interruptions, or a claim that #45’s performance targets are met.

All 38 repository tests, configuration/link checks, strict Swift formatting and whitespace checks pass. Swift 6 type-checking of the changed editor and its preference extension also passes with an explicit `arm64-apple-macosx14.0` target against the existing core module, verifying the availability guard at compilation. This does not certify runtime behavior on macOS 14. Full app builds, existing relevant native tests and final-head CI remain pending. No assertion or timeout is weakened; Intel and real IME acceptance remain separate unverified gates.
