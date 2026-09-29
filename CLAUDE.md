# workforce-images

Developer container images (base, python, java) for AI Workforce agents running on ECS and for human devcontainers. Cross-repo context lives in the workspace `CLAUDE.md` one level up, when it's present.

## Rules

- **Commit rule**: every commit is short (one logical change), testable (it comes with the check that proves it: hadolint, build, smoke test) and not breakable (CI green on its own). Conventional Commits.
- Changes land on `main` only through a squash-merged PR with green CI.
- Both consumers must keep working: ECS agent tasks and `devcontainer.json`.
- Pin tool versions with `ARG`s so updates are explicit and reviewable.
- Public repo: no secrets, AWS account IDs, emails or ARNs.

## Layout

_Skeleton in progress: images are added commit by commit._
