# Large-file opening protocol build recheck

Issue #73, source head `b18df04280e67f3be1dbd27f466aded2e1b0b653`. No product or protocol source changed during this recheck.

Environment: arm64, macOS 26.6.2 (25G83), Xcode 26.6 (17F113), Swift 6.3.3.

| Check | Command / scope | Result |
| --- | --- | --- |
| Repository automation | `python3 -m unittest discover -s Tests/RepositoryAutomationTests -v` | Passed; 57 tests, 0 failures. Includes large-open fixture generation, incomplete/invalid evidence rejection, and failure-retention checks. |
| App and test-bundle compilation | `xcodebuild build-for-testing -project NoteHush.xcodeproj -scheme NoteHush -destination 'platform=macOS,arch=arm64' -derivedDataPath build/issue73-derived CODE_SIGNING_ALLOWED=NO` | Passed; `TEST BUILD SUCCEEDED`. No tests were launched. |
| Optimized performance app | `bash scripts/build_performance.sh` | Passed; optimized app/test driver built; configuration verified; product sandbox entitlements matched. App executable SHA-256: `460cb5625c7407a4ae473e473cd5b5ead01778aebdd4efd7d43bd908ee007abb`. |
| Swift formatting | `xcrun swift-format lint --strict --recursive App Sources Tests Package.swift` | Passed |
| Configuration / whitespace | `python3 scripts/verify_configuration.py` and `git diff --check` | Passed; version 0.1.0 (1) |

The first Xcode build attempt stopped before package resolution because the workspace sandbox denied access to the developer module cache. Repeating the unchanged build with normal Xcode cache access completed successfully. No source was changed to address the environment error.

The actual 40-observation native 10 MiB opening protocol was not run in this session. It requires an explicitly arranged exclusive, awake GUI window and no competing native jobs; the prior complete baseline remains separately recorded. This build recheck does not replace a current native run, final-head hosted CI, review, minimum-OS/hardware checks, or the PRD responsiveness gate. Only generated test fixtures were used; no user documents were opened.
