#!/bin/sh
# Smoke test: every tool in the base image runs, as the unprivileged user.
set -eu

test "$(id -un)" = dev
git --version
gh --version | head -n 1
jq --version
make --version | head -n 1
node --version
npm --version
claude --version
aws --version
terraform version | head -n 1
pre-commit --version
echo "base: ok"
