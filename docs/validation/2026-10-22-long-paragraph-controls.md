# Long-paragraph font and fragment controls

Issue #75 remains unresolved. These are the first executions of the two sources prepared in the [September investigation](2026-09-09-long-paragraph-investigation.md), whose earlier readiness observer never compiled or launched them. No application source or policy changed. The [numeric index](2026-10-22-long-paragraph-controls.json) records all fourteen outcomes, exact source/driver/binary hashes, capacity/process preflights and retained artifact directories.

The Mac used the same macOS 26.6.2 / Xcode 26.6 (17F113) arm64 environment. Each matrix compiled once with Swift 6 and optimization, then ran one fresh process per cell with the original ten-second bound. Child environments were restricted to required host fields and fixed tool paths. Both preflight samples per matrix passed the unchanged disk reserve and reported no competing native processes. Sampling before execution does not prove continuous monitoring during a case. These headless public-API diagnostics use generated text, open no windows and send no input.

## Core Text font policy controls

The eight-cell matrix uses 256 KiB and 1 MiB paragraphs. `fixFonts` invokes public font-attribute repair on the unchanged mixed Arabic/emoji string; `arabicBase` supplies an available Geeza Pro base font. The other controls contain only Arabic or only emoji. Like the earlier font/run matrix, this source does not set an explicit paragraph-style attribute.

| UTF-8 size | Font repair, mixed | Arabic base font, mixed | Arabic only | Emoji only |
| --- | --- | --- | --- | --- |
| 256 KiB | First line available, 86 UTF-16 units | Timed out before typesetter creation returned | First line available, 95 units | First line available, 80 units |
| 1 MiB | Timed out before typesetter creation returned | Timed out before typesetter creation returned | First line available, 95 units | First line available, 80 units |

All cases reached the exact-text check after font preparation. The three timeouts are retained, and none of the mixed-text strategies establishes a solution. Positive cells check only the first line's range and nonzero glyph count. They do not establish complete paragraph rendering, native geometry, editing, recovery or performance acceptance. Changing script composition is a control, not a reduced replacement for the failing mixed workload.

## TextKit fragment range control

This six-cell matrix retains the complete original attributed paragraph, including an explicit natural paragraph style, in `NSTextContentStorage`. A layout-manager delegate returns either the full native range or a range capped at 4,096 UTF-16 units. Both cases still request complete document layout. The oracle checks layout availability, contiguous line coverage, exact text, line-to-source mapping and line containment inside the fragment range.

| UTF-8 size | Full native range | Partial range |
| --- | --- | --- |
| 16 KiB | Complete coverage: 8,192 UTF-16 units, 86 lines | Failed coverage (exit 65): only 4,032 units accepted by the line/range oracle |
| 256 KiB | Ten-second timeout during layout | Ten-second timeout during layout |
| 1 MiB | Ten-second timeout during layout | Ten-second timeout during layout |

The 16 KiB partial case returned only one fragment with range 0–4,096 but 86 line fragments, some outside that declared range. Its stored text and attributed text remained exact; that alone did not make its layout valid. The native-versus-partial geometry comparison consequently failed its prerequisite of complete coverage. Limiting the fragment's declared range neither produced complete valid layout nor resolved the larger cases. This approach is rejected for application integration.

## Evidence and next acceptance boundary

Exact sources and original matrix drivers are preserved in [reproducers](reproducers/README.md). Private raw outputs, including every line's numeric geometry, remain in `build/CoreTextFontPolicyProbe-3DEA42AD-18E4-422B-ADD7-E4DF6C6D9848` and `build/TextKitFragmentRangeProbe-4FB783BD-1F16-4C3C-98CA-7AD9D52C304E`. A matrix driver's successful exit means it finished recording the matrix; the individual cell statuses and coverage oracles determine outcomes. No failed cell was retried or converted into acceptance.

A future correction must establish complete native layout without changing text, paragraph breaks, bidirectional semantics, supported-file limits or deadlines. It then needs selection/undo/viewport/recovery and resource validation in the real app, original performance regressions and full CI/review. The successful multiline opening protocol and asynchronous checkpoint experiment remain separate evidence; neither closes this long-paragraph issue.
