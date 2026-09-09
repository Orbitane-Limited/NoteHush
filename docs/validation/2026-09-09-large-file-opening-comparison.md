# Native 10 MiB opening comparison, 2026-09-09

The same complete [protocol](../LARGE_FILE_OPENING.md) passes all 40 observations on both the [main-based baseline](2026-09-09-large-file-opening-baseline.md) and the integrated candidate. Each run verifies every original/recovered UTF-8 byte, file binding/identity, tab order/selection, caret/viewport, preferences/window and normal Quit, with unchanged source/app/harness and exact product sandbox before/after. No samples, failures or slow observations were removed.

| Workload | Main-based median / p95 | Candidate median / p95 | Main-based / candidate maximum |
| --- | ---: | ---: | ---: |
| 10 MiB ASCII CRLF | 280.299 / 414.136 ms | 283.150 / 586.623 ms | 485.963 / 863.711 ms |
| 10 MiB Arabic/combining-mark/emoji CRLF | 9,585.451 / 9,654.208 ms | 342.425 / 349.982 ms | 9,939.953 / 351.254 ms |

The [complete numeric comparison](2026-09-09-large-file-opening-comparison.json) preserves all samples, hashes, conditions and retained artifact references. The interval includes request delivery, app processing, recovery scheduling/I/O and independent host decoding. It is not physical display latency or proof of an interactive window. ASCII p95/max increased and remain visible; similar medians do not authorize discarding the slower observations. This comparison includes multiple candidate PRs and does not attribute every difference to a single change.

Candidate source: `30a7b7eb95d14bb8d142c2accf5045d9989ed44b`; optimized app SHA-256 `019ad90f0c499e6db91108d6001d0acf45242dd84c88bb6084808a8d3eaf9a14`. The app/core/configuration implementation remains the previously validated `9557aec`; the subsequent integration adds only the host protocol/test naming correction. Candidate build/collection envelope: 01:59:24–02:00:27 UTC. Same M4 Pro/24 GiB, macOS 26.6.2, Xcode 26.6/Swift 6.3.3, AC power, nominal initial thermal state, low-power mode off and recorded three-display configuration. Warm filesystem caches, fresh processes, user-confirmed exclusive awake GUI use and no competing CI/native measurement jobs.

All 125 integrated repository tests and 88 Swift tests, strict formatting/configuration, optimized app and Release host builds pass. The shared independent reader also passes the complete original cold/file-event/dirty-recovery/restart/independent-caret-and-scroll regression in a separate retained native run. That host retains failed fixtures, records its UUID and keeps original assertions/ten-second bounds; successful cold fixtures use the original cleanup. Its tested app binary remains `b8eef4abc2c92b425a453781c0ca0d65ca3bcf58aa46041aab4ed41f58bf1740` and the newly linked host is `643f17e0566c99d30c4c66bf814bb033362b810379aa95d7b18e86d7009c89f9`.

A separate 10 MiB unbroken mixed-script paragraph still reaches the ten-second observation limit on both main and the candidate; issue #75 tracks it. The candidate's owned-process profile identifies Core Text shaping on the main thread. Those failed diagnostics are retained separately and are not pooled into this successful multiline comparison. Their existence prevents claiming complete large-file acceptance.

Full native UI CI/review and individual issue merges remain required. The original launch/interaction protocols, physical responsiveness, minimum hardware/macOS14, memory/energy, 100 MiB and long paragraphs, Store processing/installation and publisher-specific gates remain open. Version stays 0.1.0 (1); no release, tag, installation or upload was performed. Never merge this validation branch wholesale into main.
