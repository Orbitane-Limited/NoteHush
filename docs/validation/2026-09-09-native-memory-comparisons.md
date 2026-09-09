# Native window/editor memory comparisons

Issue #67 remains unresolved. Three separate generated native apps completed a bounded diagnostic on 2026-09-09, using the same executable with window-only, empty modern text editor, and editor-plus-three-symbol-button modes. This adds framework context to the earlier allocation-origin profile; it identifies no demonstrated avoidable product allocation and changes no app code or memory budget.

| Generated variant | RSS median / p95 / maximum (MiB) | Physical footprint maximum (MiB) |
| --- | ---: | ---: |
| Window only | 76.344 / 76.344 / 76.344 | 18.860 |
| Empty TextKit 2 editor | 82.453 / 82.453 / 82.469 | 23.048 |
| Editor and three symbol buttons | 79.656 / 79.688 / 79.688 | 24.141 |

Each process settled for 30 seconds, then recorded all 61 active samples across 60 one-second intervals, verified its generated empty fixture and exited normally within its 120-second process bound. All 183 samples, timing/counter units, exact source/binary hashes, retained artifact references and four sandbox entitlements are in the [numeric evidence](2026-09-09-native-memory-comparisons.json). The source and all original outputs remain in the referenced private artifact. No user text, recovery workspace, input event or other application was accessed.

Conditions were M4 Pro/24 GiB, macOS 26.6.2, Xcode 26.6, AC power, three existing displays and warm caches. The diagnostic samples itself, so its sampler overhead is included. It is separate from the accepted product's external-host protocol. These are single sequential windows, not independent repeated estimates; their ordering and differing RSS cannot establish that adding buttons reduces memory, that displays explain a particular number, or that AppKit has a hard minimum. The diagnostic source/type name `MemoryFloor` is only a name and establishes no floor.

The accepted combined candidate still records 91.891 MiB empty RSS against the unchanged 80 MiB target, as documented in the [integrated candidate report](2026-09-09-integrated-candidate.md). Physical footprint is a different counter and does not substitute for RSS. No result here authorizes changing 80/150 MiB targets or claims M1/8 GiB, energy, platform, UI CI or release acceptance. Further implementation must follow a demonstrated avoidable allocation and the normal issue/dependency/review workflow.
