# Native component memory comparison

Issue #67 research, 2026-09-09 UTC. This is a separate, generated diagnostic app, not NoteHush acceptance or a proven minimum memory requirement. [All 183 observations and provenance](2026-09-09-native-memory-comparison.json) are retained.

A single Swift 6 optimized binary ran three fresh processes on the M4 Pro/24 GiB, macOS 26.6.2, Xcode 26.6, AC power and the same three displays. Each showed a 900 × 620-point native window, used the exact four product sandbox permissions, settled for thirty seconds and collected 61 active observations spanning at least sixty seconds. The process sampled only itself with `proc_pid_rusage`; its own JSON sampler overhead is included. Every variant exited normally, preserved its binary/signature and verified the generated editor remained empty where applicable. No user recovery, clipboard, global input or UI authorization was accessed.

| Private variant | RSS min / median / max, MiB | Physical footprint min / max, MiB |
| --- | ---: | ---: |
| Native window | 68.078 / 76.344 / 76.344 | 18.376 / 18.860 |
| Window plus empty TextKit 2 editor | 82.359 / 82.453 / 82.469 | 22.720 / 23.048 |
| Same editor plus plus/list/close symbol buttons | 79.344 / 79.656 / 79.688 | 24.141 / 24.141 |

The symbol case has a higher observed physical footprint but lower RSS than the preceding editor-only process. This is not an additive decomposition, a controlled repeated causal estimate, or evidence that removing icons would recover NoteHush's remaining RSS gap. Different process residency and self-sampler costs prevent substituting these values for the complete original app protocol. The normal app also implements recovery, tab/history controls, status, menus and other functionality absent here.

No production optimization follows from this experiment. The combined app's separately verified empty RSS remains 91.891 MiB, exceeding the unchanged 80 MiB target by 11.891 MiB. Physical footprint is not substituted for RSS; M1/minimum hardware, energy and full CI remain open.

Two storage preflights stopped preparation before any compiler/app launch. Their source/plans remain private. Headroom was restored by removing six verified-unused `ModuleCache.noindex` directories from completed NoteHush builds, with no open files. All products, packages, archives, source, traces and test evidence were preserved. The unchanged storage guard passed before the one compiled three-case run. No failed native observation was retried or discarded.

A subsequent artifact audit reverified all 183 existing observations and seven source/product/raw-output hashes; it executed no additional native case. Nearest-rank resident p95 is 76.344 / 82.453 / 79.688 MiB for window/editor/symbols respectively. The numeric index preserves these recomputed summaries alongside the unchanged original observations.
