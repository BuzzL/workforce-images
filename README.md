# workforce-images

[![CI](https://github.com/BuzzL/workforce-images/actions/workflows/ci.yml/badge.svg)](https://github.com/BuzzL/workforce-images/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)

Developer container images for the AI Workforce. The same images serve two consumers:

- **AI developer agents**, which run as ECS tasks on AWS.
- **Human developers**, through `devcontainer.json`.

| Image | Contents |
|---|---|
| `base` | git, gh, Node LTS, Claude Code, AWS CLI v2, Terraform, pre-commit |
| `python` | `base` + uv, uv-managed CPython, ruff (pytest comes from each project's dev dependencies) |

In the `python` image, uv won't download another Python on its own (`UV_PYTHON_DOWNLOADS=manual`). If a project needs a different version, run `uv python install <version>` once. It installs into your home directory.

> **Status:** early skeleton. See the [commit history](https://github.com/BuzzL/workforce-images/commits/main) for what exists so far.

## The AI Workforce repositories

| Repository | Purpose |
|---|---|
| [workforce-infra](https://github.com/BuzzL/workforce-infra) | Terraform: AWS Organization, workforce and environment accounts, cross-account roles |
| **workforce-images** | This repo: developer container images |
| [workforce-testbed](https://github.com/BuzzL/workforce-testbed) | The TypeScript codebase the agents iterate on |

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Every commit is short, testable and leaves CI green.

## License

[Apache-2.0](LICENSE)
