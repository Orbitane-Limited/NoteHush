# Cold-launch checkpoint diagnostics

The post-merge main run [40018520354](https://github.com/Orbitane-Limited/NoteHush/actions/runs/40018520354) failed in the host-only cold-launch harness with `checkpointNotObserved`. The original error did not identify which lifecycle checkpoint timed out or whether a recovery snapshot had been written. The UI test suite did not start in that run.

The same test app binary, whose app/config/project tree matches merged main `2f3b359`, passed the existing harness three consecutive times locally before the instrumentation change and once after it. These runs used only generated UUID fixtures and sent no UI input. They are comparative evidence, not proof that the hosted failure is harmless or resolved.

The harness now labels each fixed checkpoint phase and, on timeout only, reports whether the test app is active/terminated, whether its isolated recovery file exists and is readable, the snapshot revision and tab count, the selected-tab index, and whether the unchanged acceptance predicate matched. It emits no text, paths, UUIDs or bookmarks. All original 10-second deadlines and data, selection, file-byte, quit and viewport assertions remain unchanged.

Strict Swift formatting, diff checks, harness compilation and one post-change local harness run passed. Exact-head hosted CI passed on commit `31e111c735a312ef37bb41dea9f45358d39ce09d` in [run 40020535945](https://github.com/Orbitane-Limited/NoteHush/actions/runs/40020535945). The new timeout-only diagnostic did not trigger in that successful run, so the original intermittent failure is still unexplained. This passing run is not relabeled as a replacement for the recorded main-run failure.
