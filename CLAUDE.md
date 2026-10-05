# IssueCapture project instructions

Follow all project rules in `AGENTS.md` and the release procedure in `Documentation/Releasing.md`.

## Task completion and package releases

- Every time a task is finished, commit the completed changes, create a new annotated semantic-version tag, and push both the commit and tag to the package repository so dependent projects can resolve the updated package.
- Follow `Documentation/Releasing.md`: use a patch version for backward-compatible fixes, a minor version for backward-compatible API additions, and a major version for breaking changes. Never move or reuse a published tag.
- Complete any requested validation before releasing; do not run tests unless explicitly requested.
- Report the commit, version tag, and push result honestly. If release is blocked, state the blocker rather than claiming completion.
- Published versions become available to consumers; projects pinned in `Package.resolved` still need to update their package resolution.
