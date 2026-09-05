# Contributing

Choose an issue from the earliest incomplete milestone whose dependencies are closed. Branch `issue-N/description` from main, implement that issue, run the checks in TESTING.md, and open a PR with `Closes #N`.

Use concise conventional commit prefixes (`feat:`, `fix:`, `docs:`, `test:`, `ci:`, `chore:`). Prefer squash merge, delete merged issue branches, and avoid merge commits or direct pushes to main. A single empty bootstrap commit initializes the otherwise empty repository so the first docs change can use a PR.

PRs explain the user-visible result, acceptance criteria, actual tests and any limitations. Never mark an unexecuted test as passed. Do not approve your own PR or imply independent review occurred. Required status checks must pass; review with another person where available.

Use issue labels for type, area and priority; milestones for delivery stages. Dependencies are explicit issue links. Changes to scope/architecture update the docs in the same PR. Keep CHANGELOG.md current. Do not commit credentials, signing assets, user drafts, personal paths or build artifacts.

Source remains private and unlicensed for external reuse unless the owner chooses a license. Refer to AGENTS.md for implementation constraints and docs/RELEASING.md for distribution.
