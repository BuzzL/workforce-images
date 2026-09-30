# workforce-images

Developer container images (base, python) for AI Workforce agents running on ECS and for human devcontainers. Cross-repo context lives in the workspace `CLAUDE.md` one level up, when it's present.

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
  - Claude Code cannot update itself, neither in the background nor with `claude update`. `DISABLE_AUTOUPDATER` and `DISABLE_UPDATES` are set both as env vars and in root-owned `/etc/claude-code/managed-settings.json`, which wins over any environment override.
- `images/python`: FROM base (`BASE_IMAGE` build arg, **no default**, so a build never resolves a name on Docker Hub). It adds:
  - uv and ruff as prebuilt binaries in `/usr/local/bin`
  - a uv-managed CPython, root-owned under `/opt/uv/python` and linked as `python`, `python3` and `python3.X` in `/usr/local/bin`, ahead of Ubuntu's `/usr/bin/python3`
  - `UV_PYTHON_DOWNLOADS=manual`, so agents stay on the image's Python unless they explicitly run `uv python install`
  - `~/.local/bin` (uv tools) appended to PATH
  - pytest is **not** global: projects add it as a dev dependency (`uv add --dev pytest`) so it can import the project.
- Child images re-assert the base guarantees: CI runs the base smoke test in every image, then the image's own.
- `.hadolint.yaml`: lint config with `failure-threshold: style`, the same as CI, so any finding fails.

## Pinning (supply chain)

- Every downloaded tool has a version `ARG` plus `*_SHA256_AMD64` / `*_SHA256_ARM64` ARGs. The one exception is CPython in the python image: uv downloads it and verifies it against the SHA256 embedded in the pinned uv release. The **Dockerfile is the trust anchor**: to bump a tool, update the version and both hashes in the same commit. Take the hashes from the vendor checksum file or by hashing the artifact, and state the source in the PR.
- The base image is pinned by tag **and** digest, and Dependabot bumps it.
- No `# syntax=` directive: it would pull an unpinned BuildKit frontend from Docker Hub on every build.
- pre-commit and its complete dependency set are hash-pinned in `images/base/requirements/pre-commit.txt` (wheels only). They are installed with `--require-hashes --no-deps --only-binary :all:` and verified with `pip check`. The file header explains how to update it. `PRE_COMMIT_VERSION` must match it, or the build fails.
- Not pinned by hash: apt packages (GPG-verified by apt, resolved at build time, so builds aren't bit-reproducible). Automated bumps of ARG pins: see below.

## Automated pin bumps

- `scripts/bump_pins.py` (stdlib only) knows every ARG-pinned tool: node, gh, terraform, awscli, claude-code, uv, ruff and cpython. For each one it finds the latest release, skips releases younger than a **7-day cooldown**, takes the per-arch SHA256 from the vendor's checksum file (AWS CLI: by hashing the artifact) and rewrites the ARGs. node stays on its current major and cpython on its current minor.
- **`Bump pins` workflow** (weekly on Monday, or on demand with `gh workflow run bump-pins.yml -f min_age_days=N`): opens **one PR per tool** as the workforce-agent App on a `deps/<tool>-<version>` branch. CI tests each PR, and each needs maintainer approval.
- **Not automated:** pre-commit (bump it by hand together with `images/base/requirements/pre-commit.txt`), and the base image digest (Dependabot).
- **Tests:** the `scripts` CI job runs the offline unit tests (`python3 -m unittest discover -s scripts`) plus a live `--list` dry run.

## Publishing

- `.github/workflows/publish.yml` runs on a `vX.Y.Z` tag. It refuses tags whose commit is not on `main` or has no green CI run, builds each image per arch on native runners, pushes by digest, and merges the digests into a multi-arch tag set (`X.Y.Z`, `X.Y`, `X`, `sha-<short>`) on `ghcr.io/buzzl/workforce-images/<name>`.
- Authentication is the workflow `GITHUB_TOKEN` (`packages: write` only on the push jobs). No PAT.
- `python` is built `FROM` the just-published `base`, passed by digest through `BASE_IMAGE`.
- The `verify` jobs pull each published digest anonymously (so they fail while a package is still private) and run `.github/scripts/smoke.sh`, the same runner CI uses.
- New GHCR packages start private: the maintainer sets each package to public once, in the package settings.

## Consumers

- **ECS agents**: `tini -g` handles reaping and forwards SIGTERM to the whole process group, so the task definition doesn't need `initProcessEnabled`.
- **Devcontainers**: features run as root at build time, so they work. A `postCreateCommand` runs as `dev` and **cannot use apt**. Don't add the `common-utils` feature, because it would re-introduce sudo.

## Testing without local Docker

Push the branch and let CI run:
- `hadolint` lints every Dockerfile.
- `images (amd64)` and `images (arm64)` build base then python on native runners with the default docker builder (child images build `FROM` the locally loaded base), then run the smoke tests. The python image runs both the base and the python smoke test. The python one checks exact versions, read-only `/opt/uv` and site-packages, `UV_PYTHON_DOWNLOADS`, a packaged uv project with pytest on the image's Python (downloads forced off), and `uv tool install`. It checks the pinned versions (read from the ARGs), the user, the absence of sudo, read-only system paths, `npm -g`, the auto-update lock and tini.
