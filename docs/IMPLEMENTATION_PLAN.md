# Implementation Plan

Deliver sequential milestones; an issue may start only when its dependencies are satisfied. Each issue gets its own branch, acceptance tests and PR. Milestones describe end-to-end outcomes, not arbitrary sprint dates. Estimates/dates remain unset until measured progress supports them.

| Milestone | Issues | Exit criteria |
| --- | --- | --- |
| M0 — Product blueprint | 01 research/specifications and repository workflow | Research, PRD, TDD, AI context, TESTING, App Store matrix, version/release process and linked GitHub roadmap committed |
| M1 — Native foundation | 02 Swift app scaffold; 03 CI and artifact delivery | Sandboxed native app builds; version tracked; core tests and universal archive run locally and on GitHub |
| M2 — Tabs and reliable recovery | 04 versioned recovery store; 05 tab workspace and quit/relaunch integration | User can write across tabs, close without confirmation and restore correctly; corruption/errors handled visibly |
| M3 — Safe file workflows | 06 open/save and encoding; 07 bookmarks/conflicts | User-selected file workflows work in signed sandbox; external edits never silently overwritten |
| M4 — Complete editing experience | 08 search/status/navigation; 09 fonts/theme/wrap/print; 10 tab management and recent closure | All v1 editing and tab commands are complete and keyboard accessible |
| M5 — Release quality | 11 lifecycle/UI/chaos suite; 12 recovery optimization and measured budgets; 13 accessibility/compatibility | No open data-loss bug; recovery, performance, minimum/current OS and architecture evidence meet release gates |
| M6 — App Store and v1.0.0 | 14 signing/TestFlight delivery; 15 original assets/public policies/metadata; 16 release candidate, submission and GitHub release | Signed tested candidate, correct metadata, App Review outcome and real v1.0.0 GitHub release |

## Dependency graph

01 -> 02 -> 03. 02 -> 04 -> 05 -> 06 -> 07. 05 -> 08,09,10. 03+07+08+09+10 -> 11. 11 -> 12,13. 03+07 -> 14. 09+13 -> 15. 11+12+13+14+15 -> 16.

The foundation shell is intentionally a development build. M2's first full-snapshot recovery store establishes correctness, while M5 replaces hot-path full snapshots with per-tab commits and validates performance before any blazing-fast claim. M6 may begin signing preparation before M5 closes, but release cannot skip M5.

M5 performance work uses a measured baseline before the storage migration: [#30](https://github.com/Orbitane-Limited/NoteHush/issues/30) adds isolated recovery latency/I/O measurements after #11, followed by [#31](https://github.com/Orbitane-Limited/NoteHush/issues/31) for immutable tab blobs and crash-safe migration/reclamation. Separate PRs keep the measurement method and storage changes reviewable. #12 remains open for whole-app measurements and budget acceptance; a recovery microbenchmark alone cannot close it.

## Issue acceptance and traceability

Detailed baseline checklists and dependencies live in `roadmap.json` and the corresponding [GitHub issues](https://github.com/Orbitane-Limited/NoteHush/issues). GitHub retains later implementation follow-ups and edited acceptance criteria. `scripts/bootstrap_github.py` requires an explicit repository, resolves its canonical identity before mutations and reads every page of labels/milestones/issues. The default mode previews missing objects using GET requests only. `--apply` creates missing objects, matching existing ones by title and rejecting ambiguous matches; it never edits existing issue bodies. If a roadmap title changes, update the local roadmap to match before applying the preview.

```sh
# Read-only GitHub preview; no local file changes:
python3 scripts/bootstrap_github.py --repo Orbitane-Limited/NoteHush
# Refresh local links using existing remote objects, with no API mutations:
python3 scripts/bootstrap_github.py --repo Orbitane-Limited/NoteHush --write-roadmap
# Create missing objects after reviewing the preview:
python3 scripts/bootstrap_github.py --repo Orbitane-Limited/NoteHush --apply --write-roadmap
```

Local `docs/GITHUB_ROADMAP.md` is regenerated only when explicitly requested and all mapped objects exist. A failed listing or incomplete preview leaves it untouched. Run one `--apply` invocation at a time; matching is title-based. Current-operation links use the canonical owner; archived validation links remain as recorded.

| Requirements | Issues |
| --- | --- |
| NH-01, NH-02, NH-03 | 04, 05, 10, 11 |
| NH-04, NH-05 | 04, 05, 11, 12 |
| NH-06, NH-07, NH-08 | 06, 07, 11 |
| NH-09, NH-10 | 05, 08, 11, 13 |
| NH-11 | 09, 11 |
| NH-12 | 05, 10, 13 |
| NH-13 and App Store requirements | 02, 03, 14, 15, 16 |

## GitHub enforcement

Squash-only merges, branch deletion, templates, ownership, labels, pinned Actions and update automation. Configure main protection with required CI, resolved conversations, blocked force pushes/deletions and linear history when the private repository plan supports it. This is a solo-owner repository initially: automated checks plus documented self-review do not equal an independent approval. Do not create an impossible self-approval requirement. Record a GitHub plan restriction if enforcement is unavailable.

**Enforcement status, 2026-09-06:** GitHub returned HTTP 403 for main branch protection: the current plan does not support this feature for the private repository. Squash-only merge settings and automatic branch deletion are enabled. CI status reporting works independently, but required checks/PRs and blocked force pushes are procedural until a suitable plan enables enforcement. Repository visibility was not changed. Reapply protection after a plan change.

Rechecked under Orbitane-Limited on 2026-09-07: the same HTTP 403 restriction remains. The transferred repository's existing self-hosted runner is online; see [transfer verification](validation/2026-09-07-repository-transfer.md).

## Release scope changes

Features beyond v1 (multiple workspace windows/tear-out, Markdown rendering, iCloud, AI, syntax highlighting, plugins) require new issues and PRD updates. Never add them implicitly because Windows adds a feature. Production version 1.0.0 and the GitHub release remain gated by M6; development artifacts do not close distribution issues.
