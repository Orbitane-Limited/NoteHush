# Focused native Undo continuation — 2026-09-08 UTC

Issue #29. The user renewed the instruction to continue all open issue work
during the existing exclusive Mac window ending at 09:45:26 UTC.
The NoteHush runner was online/idle, no NoteHush app or XCTest run was active,
and disk headroom passed before this one-case diagnostic. Other projects were
not stopped or inspected. No system authorization UI was inspected or dismissed.

## Executed result

- Clean branch head `ca2a06d20beb2818334e01399950faf2696e2e69`; its app/test source
  is unchanged from the extended diagnostic built at `5f07390`.
- Xcode 26.6 (`17F113`); existing isolated `DebugUITesting` product and exact four
  product sandbox permissions verified before and after the run.
- One execution of the unchanged
  `EditingTests/testNativeFindReplaceUnicodeCaseAndIndependentUndo()`.
  Parallel testing disabled; original 30-second default/60-second maximum
  allowances retained. No retry or test-limit change within this invocation.
- **Passed: one test, zero failures, zero skipped.** Xcode command ran from
  07:19:51 to 07:20:37 UTC. This is command duration, not a performance sample.
- XCTest initialized and ran the actual case. The read-only Developer Tools
  status still reported disabled immediately before it. Therefore that Boolean
  alone does not explain the earlier automation-mode timeout. No security setting
  was changed by this continuation, and the historical timeout remains retained.

## App-local evidence

Only the attachment named `Isolated Undo diagnostic workspace` was exported.
Its validated generated UUID selected the exact isolated workspace; no normal
recovery store or unrelated app content was inspected.

The trace contains 49 ordered records, below the 256-record cap. It observes
three Cmd+Z events, one next-tab event, one previous-tab event and 33 other keys.
All key records use the same nonzero source-process identifier; this is not
attribution to a person or permission to inspect another process.

At every Cmd+Z, the app was active, its workspace was key, and the selected
document editor was first responder, rather than a field editor. The three
before-Undo states match the public single-replacement, case-sensitive-all and
case-insensitive-all fixtures. All three editor Undo notifications were observed;
there was no Undo notification from another manager. The unchanged native test
verified the original text afterward and independent undo across tabs.

No shutdown record was captured: the original case ends using XCTest's
`app.terminate()` teardown. This trace is not normal-Quit or flushed diagnostic
completion evidence. Those acceptance checks remain in the lifecycle suite.

## Retention and next step

Private evidence is retained in this checkout's `build/logs/` under
`UndoContinuation-8D4E75AE-0008-4E5C-A5E0-E73012DA61D8` (log, result bundle and
selected trace copies), plus `build/undo-continuation-plan.json` and allowlisted
summary. The first local preparation script assumed the newer xctestrun layout;
it stopped before execution, then used the actual format-1 target dictionary.
The original xctestrun file was preserved. A sandbox-limited result read failed;
normal Xcode result-service access succeeded.

This pass validates current diagnostic operation and the observed Find/Undo
path. It does not retroactively fix earlier input interruptions, the unidentified
dialog or the failed generated switching profile. Full CI for PR #47 was started
after the focused run completed. Its complete result must be assessed separately;
#29 remains open pending that broader evidence and an explicit residual-risk
assessment. No release, performance or independent review pass is claimed.
