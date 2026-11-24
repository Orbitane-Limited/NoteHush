# TextKit 2 layout manager queue control

Issue #75 remains unresolved. This generated-data control checks whether public `NSTextLayoutManager.layoutQueue` can keep the main loop responsive through the initial native viewport layout of the issue's exact long paragraph.

## Result

On the local arm64 MacBook Pro 16,8 (M4 Pro, macOS 26.6.2, Xcode 26.6 / Swift 6.3.3), the probe used the 10,485,760-byte generated fixture from the issue, retained the expected UTF-16 length, and computed source SHA-256 `e4e0a3ac39ad74b9b5d4b0b6c85e46ba7d1ea2f6c7ddd4c287f0e1e07effdd63`. `NSTextLayoutManager.layoutQueue` was a serial user-initiated operation queue, and the source compiled with a macOS 14.0 deployment target.

The main-run-loop heartbeat fired at 0.110 and 0.210 seconds while the manager queue had zero operations. The probe then requested `textViewportLayoutController.layoutViewport()`. It printed `before-layoutViewport queue=0` and did not return within the unchanged 10.5-second external process bound. The timeout ended only this isolated generated-fixture probe. The complete stdout/stderr, Swift source and hashes are retained in the companion files and `/private/tmp/NoteHushManagerLayoutQueue-20261029/`.

This is a failed bounded viewport observation, not a completed rendering result. The heartbeat only shows that the app's main loop can run before the synchronous viewport request. It does not show completed background layout, visible output, interaction, exact selection geometry or an integrated editor. This control therefore does not establish a correction and changes no application code, input limit or timeout.

## Reproduction

```sh
swiftc -parse-as-library -target arm64-apple-macosx14.0 -swift-version 6 -O \
  TextKitLayoutManagerQueueViewportProbe.swift \
  -framework AppKit -framework CryptoKit -o TextKitLayoutManagerQueueViewportProbe
python3 - <<'PY'
import subprocess
subprocess.run(["./TextKitLayoutManagerQueueViewportProbe"], timeout=10.5, check=True)
PY
```

The expected negative result is `subprocess.TimeoutExpired` after the probe prints `before-layoutViewport`. Do not interpret that timeout as a pass.

Source SHA-256: `8b690318e648f48b203919c678678a04d1b937301ed59e4726dbef12f02f945c`; binary SHA-256: `93ede0e505753d363caa11fa71fbf9302606bc0a8f35f83061268a0f9a1c9145`. The bounded run elapsed 10.517 seconds and the raw stderr is in [`TextKitLayoutManagerQueueViewportProbe.log`](reproducers/TextKitLayoutManagerQueueViewportProbe.log).
