# Application performance measurement

Issue [#35](https://github.com/Orbitane-Limited/NoteHush/issues/35) prepares repeatable native-app measurements for [#12](https://github.com/Orbitane-Limited/NoteHush/issues/12). The isolated host setup and cleanup have [passed a functional check](validation/2026-09-07-performance-harness-setup.md); the measurement suite is still under validation and no application-launch result has been recorded yet. Record the final baseline only after #31 is merged. Storage-only benchmark results do not certify app latency.

## Isolated optimized app

`ReleasePerformance` builds the same AppKit implementation with Swift `-O` and whole-module optimization, using bundle ID `pk.codehub.NoteHush.PerformanceTesting`. It requires `NOTEHUSH_TEST_WORKSPACE` to be a UUID before `NSApplication` is created. The directory is derived inside this separate app container; arbitrary paths and reset flags are not accepted. Its run, test, profile, archive and analyze actions all use this configuration. The normal Release app excludes the readiness signpost and workspace environment handling; archive validation checks both metadata and the executable for accidental test controls.

The `NoteHushPerformance` scheme disables its debugger and diagnostic instrumentation for measurement. The functional `NoteHush` CI scheme retains its existing checks, tests and 30/60-second per-case limits. Performance cases have a separate allowance because each performs 20 full launches; this is not a change to a failing functional test's timeout.

`build_performance.sh` compiles the optimized app and test driver without launching either. Normal CI runs this build after its functional tests and shipping archive checks. `verify_performance_build.py` checks resolved build settings and every scheme action. `verify_test_app.py --configuration ReleasePerformance` checks the separate app identity, required workspace marker and exact four product entitlements. Both checks must pass before any performance launch. Test builds are never release archives or App Store candidates.

## Measurements and boundaries

The three cases use an empty tab, 20 open tabs totaling 5 MiB, and 100 open plus 20 closed tabs totaling 30 MiB. Nonempty tabs each contain 256 KiB, alternating unique ASCII and Arabic/combining-mark/emoji CRLF fixtures. The selected tab is deliberately the last tab. The host-only `PerformanceFixtureHarness` first checks missing/invalid workspace rejection, makes untimed launches to register the sandbox container, then seeds each fixture after the app terminates. The sandboxed XCTest runner reads only generated fixture identities and digests from a manifest; it does not write another app's container. Every measured iteration launches a new process against warm filesystem caches. This is not post-reboot cold launch.

Each case requests 20 XCTest measurement iterations. XCTest performs an additional first warm-up iteration and excludes that iteration from its reported measurements; the driver does not remove further samples. Extraction must verify the actual exported sample count and units before calculating an arithmetic middle-pair median and nearest-rank p95. Retain the raw xcresult/CSV/JSON data and identify that framework warm-up. Do not silently accept missing signpost intervals or too few measurements. Collection stops explicitly after the restored editor is available and before post-interval assertions or Quit, so the launch metric can detach its event-loop observer while the process is alive.

Report two separate intervals:

- `XCTApplicationLaunchMetric(waitUntilResponsive: true)` reports Apple's first-frame/main-thread-responsiveness launch metric. An asynchronous recovery operation can outlast the initial window, so this metric alone does not establish editor readiness.
- `ProcessToEditorReady` starts in the app entry point after workspace-identity validation and ends after recovery, selected-editor installation, focus, layout and `displayIfNeeded`. This excludes pre-entry loader/LaunchServices work, and its endpoint is an AppKit readiness boundary rather than display scan-out. It must not be relabeled as event-to-visible typing latency or added to an overlapping launch interval.

Static signpost names contain no document content, paths, bookmarks or clipboard data. After the measured intervals, the driver checks selected-tab identity/text, types a generated character into the restored keyboard destination, undoes it and verifies the original digest. It then uses Cmd+Q and verifies both XCTest state and the identified process have terminated. Every iteration must start without a running app; all open/closed buffers are verified after the final normal termination. Generated fixture storage is removed only after the owned test app stops. The suite refuses to take over a previously running performance app.

## Running and retaining evidence

Wait until CI and other GUI automation are finished. Use a logged-in desktop with exclusive keyboard/mouse access, fixed display conditions, AC power and recorded power/thermal state. Do not run the functional UI suite or another local performance run concurrently. Do not stop or inspect unrelated projects to obtain a result.

```sh
bash scripts/test_performance.sh
```

The script validates configuration, builds the optimized app/tests, applies and checks the exact sandbox signature, runs the opt-in suite and exports metrics with `xcresulttool`. The host helper verifies all open/closed buffer digests and selection after normal termination, then removes only its generated performance-workspace directories. Existing fixture manifests or an already-running performance app stop setup; failed cleanup leaves evidence for inspection. Logs, provenance and a unique result bundle are retained under `build/logs`. Raw extraction and the first full run remain outstanding while #31 is in CI. Do not present this unfinished harness as measured app performance.

The manually dispatched `Application performance` workflow runs the same command and retains evidence for 14 days. Its job shares the single self-hosted runner with functional CI, so those jobs cannot run concurrently. This does not prevent input from a person, local command or another project; the operator still needs to establish exclusive GUI access. No automatic reruns or latency thresholds are configured.

The scripts record source revision/dirty state, executable hash, macOS/Xcode/Swift versions, hardware model/memory/architecture, cache/power conditions, screen sizes/scales and initial thermal state. Thermal enum values are 0 nominal, 1 fair, 2 serious, 3 critical; the fixture timestamp is Foundation's seconds since 2001-01-01. The record explicitly leaves other GUI input exclusivity unverified. Document sample counts, display changes and competing workloads separately; a dirty checkout is acceptable for harness debugging, not the final reproducible baseline. Compare unprofiled samples separately from Instruments runs. Failure or interruption invalidates that result set; investigate it without trimming slow samples or changing functional assertions.

Power metadata retains only a recognized power source, internal-battery percentage and charging state. Battery identifiers, device names and raw command output are excluded; unfamiliar values remain unknown. These are initial conditions, not continuous monitoring of the full run.

## Instruments protocol

The installed Xcode 26.6 provides App Launch, Time Profiler, CPU Profiler, Allocations and Power Profiler templates. `xctrace record` supports targeting a single launched app or PID, and `xctrace export` exposes a trace table of contents plus XPath-selected tables. Only the independently verified PerformanceTesting app and generated fixtures are in scope. Never use `--all-processes`, attach to an unrelated process, or profile the user's regular NoteHush workspace.

`bash scripts/profile_performance.sh` builds/verifies the app and prepares separate fixtures. The host helper invokes `xcrun xctrace record --template 'Time Profiler' --time-limit 10s --output <unique.trace> --env NOTEHUSH_TEST_WORKSPACE=<generated UUID> --launch -- <verified performance executable>` for the 5 MiB workspace. It checks the launched app identity, requests normal termination if Instruments leaves it running, verifies recovered fixture buffers, and exports the trace table of contents. Only a process launched for this operation is eligible for forced failure cleanup. It never passes `--all-processes` or `--no-prompt`.

Retain the trace and exported table of contents, inspect the app's samples and document profiler overhead separately. A denied profiling permission or unavailable metric is an unverified gate; do not broaden shipping entitlements or imply a successful trace. The first isolated profiling run, trace verification and findings remain outstanding.

## Remaining product acceptance

#12 still requires event-to-visible typing, switching, 10/100 MiB and pathological-line behavior, memory/resident footprint, settled 60-second idle CPU/energy, display/font/wrap/spelling/printing responsiveness and 100+ tabs/history operations. The M1/8 GB reference hardware is not available in this session; M4 Pro results cannot silently stand in for it. Minimum-macOS/Intel, VoiceOver, real IMEs and signed TestFlight behavior remain separate open release gates. Do not revise limits or publish speed claims without evidence.

References checked against the installed SDK and official documentation: [XCTApplicationLaunchMetric](https://developer.apple.com/documentation/xctest/xctapplicationlaunchmetric), [OSSignposter](https://developer.apple.com/documentation/os/ossignposter), and [XcodeGen 2.46.0 scheme options](https://github.com/yonaskolb/XcodeGen/blob/2.46.0/Docs/ProjectSpec.md#scheme). Installed `XCTMetric.h` confirms the macOS launch/readiness metric API; `xctrace help record/export` and `xcresulttool export metrics --help` document the CLI used here.
