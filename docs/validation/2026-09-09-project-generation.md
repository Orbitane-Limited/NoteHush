# Xcode project encryption declaration

Issue #69; checked 2026-09-09 local time with XcodeGen 2.46.0. Baseline main `bb49b49c5cb3ead161f774d087d9fd26481f73e1`.

Running the documented generator removed `ITSAppUsesNonExemptEncryption` from the generated plist because `project.yml` omitted it. The existing configuration check rejected the missing declaration while preparing #68. That branch restored the original plist before its successful archive.

The fix declares the already audited boolean `false` in the app target’s `info.properties`. Two separate generated-project fixtures retain before/after source, output and logs under local `build/project-generation-D562CFC9-77BE-4810-ADA5-36CEE0497445/`. Both generator commands succeeded. The original source omitted the generated declaration; the corrected source produced the exact original plist dictionary, including all version, test-isolation and document-type properties. See the [numeric result](2026-09-09-project-generation.json).

The checked-in project and Info.plist already contained the desired product configuration, so they require no semantic change. No app source, entitlement, audit conclusion or version changed. Local configuration/relative-link checks, 45 repository tests and `git diff --check` pass. Full required CI remains pending on the self-hosted runner’s Automation Mode prerequisite. No release or new export declaration was submitted.
