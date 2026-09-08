# Input-source diagnostic preparation

Date: 2026-09-08. Issue #29. Parent source `d45b7b64512d3218aece6a067ca4c513d722081f`. This change does not fix or attribute the earlier native input interruption.

## Evidence requiring clarification

The user authorized ten hours of exclusive Mac use. One unchanged focused XCTest attempt timed out while enabling automation mode, before app setup or test execution. It was not retried and does not establish a product assertion failure. No automation/security policy was changed.

Later, on combined preparation source `984df3737918b38120eb66b968511d1dfd26e391`, an app-only mixed-script switching profile had two computer-use state-refresh notices during setup. After refresh and one declared warm-up, all 40 serialized command receipts matched their expected counter, selected tab and editor focus. Nevertheless, the recorder failed to finalize within its declared bound, and post-termination verification found one additional byte at the ASCII tab's original caret and moved selection/scroll state in the mixed-script tab. The unexpected byte was not logged. Both retained recovery generations had valid checksums. This failed run cannot qualify performance or recovery acceptance.

Neither the state-refresh notices nor the observed edit identify a person, competing automation, event-synthesis fault or app defect. The source remains unknown. The owned fixture app was terminated normally; its failed recovery generations and partial trace remain private and unchanged. Keyboard-driven validation is paused pending clarification about exclusive input. Read-only NoteHush Actions queries showed no queued or running repository job. No unrelated app, global input stream or system dialog was inspected.

## Additional observations

Only the existing opt-in `DebugUITesting` local monitor changes. It still returns the original event unchanged, uses the exact isolated bundle/UUID, caps all records at 256 and writes through the existing ordered actor. Normal Debug, Release and ReleasePerformance exclude it.

- Cmd+Z, Control+Tab and Control+Shift+Tab receive fixed categories; every other key is only `otherKey`.
- Each key observation records `isARepeat`, whether its window is the identified workspace, and an optional nonnegative Int32 event-source PID from the existing event's CGEvent. No character or key code is retained.
- A missing/zero source is unknown. A source number alone cannot establish human involvement or delivery after the local monitor. It does not authorize inspecting that process.
- The existing bounded public-oracle classification remains unchanged. Unexpected input is only `other`; it is never emitted or hashed by the probe.
- The strict summary accepts older traces without invented metadata, rejects malformed source IDs, incomplete key flags, metadata on unrelated event classes and all extra payload/key-code fields. Missing shutdown and record-cap truncation remain explicit limitations.

The public APIs were checked in the installed macOS SDK headers and Apple's documentation: [event-source process ID](https://developer.apple.com/documentation/coregraphics/cgeventfield/eventsourceunixprocessid), [repeat status](https://developer.apple.com/documentation/appkit/nsevent/isarepeat), and [local event monitoring](https://developer.apple.com/documentation/appkit/nsevent/addlocalmonitorforevents(matching:handler:)). These APIs describe observations, not an attribution guarantee.

## Validation status

All 41 repository tests and 85 core tests with coverage pass. Strict Swift formatting, configuration/relative links and diff checks pass. `DebugUITesting` build-for-testing, normal Debug, universal unsigned Release archive and optimized ReleasePerformance build-for-testing all pass. The two isolated products have exactly the four product sandbox entitlements. The extended diagnostic markers are present in the actual isolated app code library and absent from the three other products, including adjacent dynamic libraries. Private build logs and the complete per-artifact SHA-256 manifest are retained as `build/logs/key-diagnostic-*`.

No native execution of the extended probe, passing full CI, resolved input cause or independent review is claimed. Any future native run must first satisfy the original exclusive-input protocol, use a new generated fixture and retain its complete outcome without retries or weakened assertions.
