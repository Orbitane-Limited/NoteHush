# Legacy TextKit wrapping-mode control

Issue #75 remains open. This headless control was recorded before the shipping editor moved to TextKit 2 in PR #72. It tests whether changing a long unbroken mixed-script paragraph from TextKit 1 word wrapping to character wrapping changes that layout manager's cost. It is a historical comparison, not a measurement of the current editor.

The optimized probe used the exact generated 10 MiB Arabic/emoji paragraph form at 1 MiB and 10 MiB, with a 10-second limit for each fresh process. Both word-wrapping and character-wrapping cases timed out at both sizes before complete glyph/character coverage could be reported. Explicitly disabling default hyphenation did not prevent the stalls. Character wrapping therefore did not establish a correction; no layout geometry comparison was possible.

This isolated `NSTextStorage`/`NSLayoutManager` probe opens no window and reads no user file. Its exact [numeric matrix](2026-10-23-legacy-wrap-mode.json), source hash, binary hash and private artifact directory are retained. The [probe source](reproducers/LegacyWrapModeProbe.swift) and [self-compiling runner](reproducers/run-legacy-wrap-mode-probe.py) are reproducible. This is diagnostic evidence only; it does not verify the view, editing, IME, undo, recovery or release performance.
