# Repository transfer verification

Issue [#27](https://github.com/Orbitane-Limited/NoteHush/issues/27), recorded 2026-09-07. The canonical repository is `Orbitane-Limited/NoteHush`. GitHub transfer affects automation routes and current-operation links; the application signing identity is a separate release configuration.

## Implemented safeguards

The bootstrap requires `--repo OWNER/REPOSITORY`, pins requests to github.com, resolves canonical `full_name` with a GET and uses it for subsequent requests. Collection reads use `gh api --paginate --slurp`; all reads and title/dependency checks complete before mutations. The default mode previews only. `--apply` creates missing objects without editing existing bodies, and `--write-roadmap` explicitly regenerates the local link document only when every mapped object exists.

The offline suite covers transfer routing, all-page transport, PR exclusion, ambiguous matching titles, malformed repository input, dependency ordering, exact JSON/newline transport, read-only previews, incomplete/failed listing preservation and idempotent creation. Eleven tests passed with fake GitHub responses and temporary files; the script's mutation mode was not needed for live verification.

## Live verification

The canonical runner API reported `NoteHush-Mac-arm64` online, idle immediately before the isolated performance baseline, and subsequently serving the benchmark PR's CI. Existing runner registration and credentials were retained. No runner directory or other project's processes were modified.

`gh api repos/Orbitane-Limited/NoteHush/branches/main/protection` returned HTTP 403: the private repository's plan requires an upgrade to enable branch protection. Green checks, resolved review and manual squash merging remain required procedures; no independent approval is invented. Repository visibility was retained.

The live command `python3 scripts/bootstrap_github.py --repo Orbitane-Limited/NoteHush --write-roadmap` completed in preview mode with empty missing-label, missing-milestone and missing-issue lists. It resolved all 16 baseline issue numbers and regenerated the local roadmap using GET requests only. Archived validation documents keep their historical links. No duplicate milestones/issues or issue-body edits were needed. The PR records the final self-hosted checks on its full head.

A second read-only preview using `--repo CodeHubdotPk/NoteHush` followed the existing GET redirect, reported `Orbitane-Limited/NoteHush` as canonical, and produced the same empty missing-object lists and canonical issue URLs. No local output file was requested in this alias check.

## References

- [GitHub repository metadata API](https://docs.github.com/en/rest/repos/repos#get-a-repository)
- [GitHub redirect guidance](https://docs.github.com/en/rest/using-the-rest-api/best-practices-for-using-the-rest-api#follow-redirects)
- [GitHub CLI API pagination](https://cli.github.com/manual/gh_api)
