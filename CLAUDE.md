# workforce-images

Developer container images (base, python, java) for AI Workforce agents running on ECS and for human devcontainers. Cross-repo context lives in the workspace `CLAUDE.md` one level up, when it's present.

## Rules

- **Commit rule**: every commit is short (one logical change), testable (it comes with the check that proves it: hadolint, build, smoke test) and not breakable (CI green on its own). Conventional Commits.
- Changes land on `main` only through a squash-merged PR with green CI.
- Both consumers must keep working: ECS agent tasks and `devcontainer.json`.
- Pin tool versions with `ARG`s so updates are explicit and reviewable.
- Public repo: no secrets, AWS account IDs, emails or ARNs.

## Layout

- `images/<name>/Dockerfile` has one image per folder, with its `smoke.sh` next to it. The smoke test runs inside the built image in CI.
- `images/base`: Ubuntu 26.04, non-root user `dev` (UID 1000, **no sudo**), with Node LTS, gh, Terraform, AWS CLI v2, pre-commit and Claude Code (auto-update disabled; bump `CLAUDE_CODE_VERSION`).
- Tool versions are `ARG`s at the top of each Dockerfile. Downloads are sha256-verified where the vendor publishes checksums.
- `.hadolint.yaml`: lint config; CI fails on warnings.

## Testing without local Docker

Push the branch and let CI run: `hadolint` lints every Dockerfile, and `images` builds each image and runs its smoke test.
