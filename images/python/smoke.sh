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
# Test fixture only: pytest is a project dependency, not part of the image.
PYTEST_VERSION=9.1.1

expect_version uv "${UV_VERSION}" "$(uv --version)"
expect_version python3 "${PYTHON_VERSION}" "$(python3 --version)"
expect_version python "${PYTHON_VERSION}" "$(python --version)"
expect_version "python${PYTHON_VERSION%.*}" "${PYTHON_VERSION}" "$("python${PYTHON_VERSION%.*}" --version)"
expect_version ruff "${RUFF_VERSION}" "$(ruff --version)"

for dir in /opt/uv/python /opt/uv/tools; do
  [[ -d "$dir" ]] || fail "$dir missing"
  [[ ! -w "$dir" ]] || fail "$dir is writable by $(id -un)"
done
echo "ok  uv-managed python and tools read-only"

# End to end: a project with pytest as a dev dependency, on the image's Python.
project="$(mktemp -d)/smoke"
uv init --quiet --no-readme --python "${PYTHON_VERSION}" "$project"
cd "$project"
uv add --quiet --dev "pytest==${PYTEST_VERSION}"
mkdir tests
printf 'from main import main\n\n\ndef test_main():\n    main()\n' > tests/test_main.py
uv run --quiet python -m pytest -q -p no:cacheprovider tests
expect_version pytest "${PYTEST_VERSION}" "$(uv run --quiet python -m pytest --version)"
expect_version "project python" "${PYTHON_VERSION}" "$(uv run --quiet python --version)"
[[ ! -e "$HOME/.local/share/uv/python" ]] || fail "uv downloaded its own Python instead of using the image's"
ruff check --quiet . && ruff format --check --quiet .
echo "ok  uv project with pytest"

echo "python: ok"
