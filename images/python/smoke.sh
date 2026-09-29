#!/usr/bin/env bash
# Smoke test for the python image (run after the base smoke test, in the same
# image). Expected versions come from the Dockerfile ARGs via environment.
set -euo pipefail

fail() { echo "FAIL: $*" >&2; exit 1; }
expect_version() { # <name> <expected> <actual output>
  [[ "$3" =~ (^|[^0-9.])"$2"($|[^0-9.]) ]] || fail "$1: expected $2, got: $3"
  echo "ok  $1 $2"
}

: "${UV_VERSION:?}" "${PYTHON_VERSION:?}" "${RUFF_VERSION:?}"
# Test fixtures only: they are installed by the test, not part of the image.
PYTEST_VERSION=9.1.1
PYCOWSAY_VERSION=0.0.0.2

expect_version uv "${UV_VERSION}" "$(uv --version)"
expect_version python3 "${PYTHON_VERSION}" "$(python3 --version)"
expect_version python "${PYTHON_VERSION}" "$(python --version)"
expect_version "python${PYTHON_VERSION%.*}" "${PYTHON_VERSION}" "$("python${PYTHON_VERSION%.*}" --version)"
expect_version ruff "${RUFF_VERSION}" "$(ruff --version)"

purelib="$(python3 -c 'import sysconfig; print(sysconfig.get_paths()["purelib"])')"
for dir in /opt/uv /opt/uv/python "$purelib"; do
  [[ -d "$dir" ]] || fail "$dir missing"
  [[ ! -w "$dir" ]] || fail "$dir is writable by $(id -un)"
done
echo "ok  uv-managed python read-only"

[[ "${UV_PYTHON_DOWNLOADS:-}" == manual ]] || fail "UV_PYTHON_DOWNLOADS must be manual"
echo "ok  implicit python downloads disabled"

# From here on any interpreter download fails loudly.
export UV_PYTHON_DOWNLOADS=never

# End to end: a packaged project with pytest as a dev dependency. No Python
# version is requested, so this also proves which interpreter uv picks.
project="$(mktemp -d)/smoke"
uv init --quiet --package --no-readme "$project"
cd "$project"
uv add --quiet --dev "pytest==${PYTEST_VERSION}"
mkdir tests
printf 'from smoke import main\n\n\ndef test_main():\n    main()\n' > tests/test_main.py
uv run --quiet python -m pytest -q -p no:cacheprovider tests
expect_version pytest "${PYTEST_VERSION}" "$(uv run --quiet python -m pytest --version)"
expect_version "project python" "${PYTHON_VERSION}" "$(uv run --quiet python --version)"
base_prefix="$(uv run --quiet python -c 'import sys; print(sys.base_prefix)')"
[[ "$base_prefix" == /opt/uv/python/* ]] || fail "project uses $base_prefix, not the image's Python"
ruff check --quiet .
ruff format --check --quiet .
echo "ok  uv project with pytest on the image's Python"

# uv tools install for dev and are on PATH.
uv tool install --quiet "pycowsay==${PYCOWSAY_VERSION}"
[[ "$(command -v pycowsay)" == "$HOME/.local/bin/pycowsay" ]] || fail "uv tool not on PATH"
pycowsay moo >/dev/null
echo "ok  uv tool install"

echo "python: ok"
