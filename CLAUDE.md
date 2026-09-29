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
- `images/base`: Ubuntu 26.04 (pinned by digest), with Node LTS, gh, Terraform, AWS CLI v2, pre-commit, Claude Code, and `tini` as PID 1.
  - Runs as the unprivileged user `dev` (UID/GID 1000) with **no sudo**.
  - `npm -g` installs to `~/.npm-global`, which comes **last** on PATH so it can't shadow system tools.
  - Claude Code self-update is disabled through the env var and root-owned `/etc/claude-code/managed-settings.json`.
- `.hadolint.yaml`: lint config. The CI action fails on any finding.

## Pinning (supply chain)

- Every downloaded tool has a version `ARG` plus `*_SHA256_AMD64` / `*_SHA256_ARM64` ARGs. The **Dockerfile is the trust anchor**: to bump a tool, update the version and both hashes in the same commit. Take the hashes from the vendor checksum file or by hashing the artifact, and state the source in the PR.
- The base image is pinned by tag **and** digest, and Dependabot bumps it.
- Not yet pinned by hash: apt packages (they come from the digest-pinned base) and pre-commit's pip dependencies (tracked in an issue).

## Consumers

- **ECS agents**: `tini` handles signals and reaping, so the task definition doesn't need `initProcessEnabled`.
- **Devcontainers**: features run as root at build time, so they work. A `postCreateCommand` runs as `dev` and **cannot use apt**. Don't add the `common-utils` feature, because it would re-introduce sudo.

## Testing without local Docker

Push the branch and let CI run:
- `hadolint` lints every Dockerfile.
- `images (amd64)` and `images (arm64)` build on native runners and run `smoke.sh`. It checks the pinned versions (read from the ARGs), the user, the absence of sudo, read-only system paths, `npm -g`, the auto-update lock and tini.
