# Store bundle and capacity guards, 2026-09-09

Issue #52 / PR #61 now applies the existing icon and encryption audit to both signed archive and exported package contents. Previously, the delivery checker validated source configuration but could accept a bundle with a missing/incorrect encryption flag or icon declaration. The bundle now requires Boolean `false`, both original icon fields and a nonempty regular compiled icon; symlinks are rejected. Privacy-manifest equality remains required.

The workflow checks current capacity before the signing job. The driver repeats the unchanged 20 GiB/10% reserve before reading signing inputs, after archiving before export, and after export before package expansion. Both jobs retain the standard numeric capacity reports, including on failure. Source/CI, signing ownership/cleanup, versioning and upload authorization checks remain in force.

Implementation: clean `7401c05c9f89f27abee5a4334f7cf753b14c0e18`.

| Validation | Result |
| --- | --- |
| Regression reproduction against the previous implementation | Four new tests produced 19 failing subcases, including missing guards; retained locally |
| Final repository suite | All 84 tests passed in 2.326 seconds, no skipped tests |
| New failure coverage | Five tests reject incorrect encryption types, changed icon metadata, missing/empty/directory/symlink icons, initial low space, and capacity loss after archive/export; next native stage and upload must not run |
| Configuration, relative links and whitespace | Passed |
| Retained official actionlint 1.7.12 | Passed; optional ShellCheck/pyflakes integrations unavailable and not claimed |
| Existing engineering Store package | New metadata/resource checks passed without native commands; package SHA-256 unchanged |

The package remains `0.1.0 (1)`, SHA-256 `5102f181b28447192836529659cfcda5022ae58d5e52ff34db5e3051cefc88c6`; its compiled icon is 13,099 bytes. This additional inspection does not rebuild, resign, launch, upload or certify installation. App code is unchanged by these delivery fixes.

The first complete repository invocation inside the command sandbox had one error: the preexisting public-certificate extraction test returned no extracted file. A separate, read-only extraction outside that sandbox produced the three public certificate files. The complete unchanged assertions then passed outside the command sandbox, including the final clean-commit run. Earlier outputs are retained; no private signing key was accessed by this diagnosis. The initial missing `actionlint` PATH lookup was resolved using the previously downloaded, checksum-verified local tool.

Full final-head UI CI and PR review remain required. Automation Mode still requires owner authentication, and current storage is below the native-run reserve. No additional native app workload or upload was attempted. Parent #14 remains open for Store access, processing and installed TestFlight acceptance; this does not authorize a release.
