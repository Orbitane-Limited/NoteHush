# Global undo across native text slices

**Date:** 2026-10-31  
**Status:** Isolated AppKit diagnostic only. This is not integrated into `EditorTab`.

## Method

The probe creates a 300,000 UTF-16-unit generated RTL/emoji document and a native `NSTextView` whose storage contains only an 800-unit slice. It inserts one character at global UTF-16 offset 150,040, rebinds the text view to the slice at offset zero, then invokes Undo and Redo through the view's Objective-C actions. It checks exact UTF-16 source contents, the global caret, and Undo/Redo menu validation.

The control that returns the same `UndoManager` to native text editing and document-level operations fails to restore the exact source after rebinding. The passing control gives `NSTextView` a separate native manager, stores edit inverses in document-level history, routes Undo/Redo actions to that history, and validates menu state against it. This keeps AppKit's slice-local inverse out of the document-level undo group.

## Result

The separate-manager control restored the original source and global selection after Undo, then restored the edited source and post-edit selection after Redo. The same-manager control failed the exact-source check. Both controls use direct `NSTextView.insertText` calls in an isolated hidden window; physical keyboard dispatch, real IME composition, grouped typing, long-document layout, app recovery, accessibility, and application integration remain unverified.

This identifies a viable undo-isolation mechanism for further integration. It does not establish that the virtual editor is safe to ship or resolve issue #75.

## Reproduction

Built and run on arm64, macOS 26.6.2, Swift 6.3.3, Xcode 26.6 (17F113). Swift compiler warnings were treated as errors. Source SHA-256: `27e263d144ae6efe29f96f88cf12e133dc11f039356fcd46e081d1ca3d11e40d`; output SHA-256: `fe58775bb7ee9e6f451798e5024cc1c822456fc3f92a0cb16e567120f1182841`.

```sh
mkdir -p /private/tmp/NoteHushUndoModuleCache
CLANG_MODULE_CACHE_PATH=/private/tmp/NoteHushUndoModuleCache xcrun swiftc \
  -module-cache-path /private/tmp/NoteHushUndoModuleCache -swift-version 6 \
  -warnings-as-errors -O -parse-as-library -target arm64-apple-macosx14.0 \
  docs/validation/reproducers/GlobalUndoAcrossNativeSliceProbe.swift \
  -framework AppKit -o /private/tmp/NoteHushGlobalUndoProbe
/private/tmp/NoteHushGlobalUndoProbe
```

The complete numeric output is retained in [`2026-10-31-global-undo-across-native-slices-output.txt`](2026-10-31-global-undo-across-native-slices-output.txt). The probe uses generated text only and prints no source contents.
