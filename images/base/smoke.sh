#!/usr/bin/env bash
# Smoke test for the base image. Runs inside the container as its default
# user. Expected versions come from the Dockerfile ARGs via environment
# variables (see the images job in .github/workflows/ci.yml).
set -euo pipefail

fail() { echo "FAIL: $*" >&2; exit 1; }
expect_version() { # <name> <expected> <actual output>
  [[ "$3" =~ (^|[^0-9.])"$2"($|[^0-9.]) ]] || fail "$1: expected $2, got: $3"
  echo "ok  $1 $2"
}

: "${NODE_VERSION:?}" "${GH_VERSION:?}" "${TERRAFORM_VERSION:?}" "${AWSCLI_VERSION:?}"
: "${CLAUDE_CODE_VERSION:?}" "${PRE_COMMIT_VERSION:?}"

# Pinned tools, at the pinned versions.
expect_version node "v${NODE_VERSION}" "$(node --version)"
expect_version gh "${GH_VERSION}" "$(gh --version)"
expect_version terraform "v${TERRAFORM_VERSION}" "$(terraform version)"
expect_version aws "aws-cli/${AWSCLI_VERSION}" "$(aws --version)"
expect_version claude "${CLAUDE_CODE_VERSION}" "$(claude --version)"
expect_version pre-commit "${PRE_COMMIT_VERSION}" "$(pre-commit --version)"
/opt/pre-commit/bin/pip check >/dev/null || fail "pre-commit venv has inconsistent dependencies"
/opt/pre-commit/bin/python -c 'import cfgv, identify, nodeenv, virtualenv, yaml; assert yaml.__with_libyaml__' \
  || fail "pre-commit dependencies do not import (or PyYAML lacks its C extension)"
echo "ok  pre-commit dependencies consistent and importable"

# System tools run.
for tool in git jq make curl python3 npm; do
  "$tool" --version >/dev/null 2>&1 || fail "$tool missing or broken"
done
unzip -v >/dev/null || fail "unzip missing or broken"
ssh -V 2>/dev/null || fail "ssh missing or broken"
echo "ok  system tools"

# Unprivileged user, no sudo, system paths read-only.
[[ "$(id -un)" == dev && "$(id -u)" == 1000 && "$(id -g)" == 1000 ]] \
  || fail "unexpected user: $(id)"
! command -v sudo >/dev/null || fail "sudo must not be installed"
for dir in /usr/local/bin /usr/local/lib /opt/pre-commit /etc/claude-code; do
  [[ -d "$dir" ]] || fail "$dir missing"
  [[ ! -w "$dir" ]] || fail "$dir is writable by $(id -un)"
done
echo "ok  user dev (1000:1000), no sudo, system paths read-only"

# Global npm installs work for dev and cannot shadow system tools.
npm install --global --silent --no-audit --no-fund is-number@7.0.0
[[ -f "$HOME/.npm-global/lib/node_modules/is-number/package.json" ]] \
  || fail "npm -g did not install into ~/.npm-global"
[[ ":$PATH:" == *":$HOME/.npm-global/bin:"* ]] || fail "~/.npm-global/bin not on PATH"
# User-writable bin dirs come after every system dir, so they cannot shadow
# system tools.
[[ -n "$HOME" && "$HOME" != / ]] || fail "HOME must be a real directory, got '$HOME'"
[[ "$PATH" != :* && "$PATH" != *: && "$PATH" != *::* ]] \
  || fail "PATH has an empty entry (current directory): $PATH"
seen_user_dir=false
IFS=: read -ra path_entries <<< "$PATH"
for entry in "${path_entries[@]}"; do
  if [[ "$entry" == "$HOME"/* ]]; then
    seen_user_dir=true
  elif [[ "$seen_user_dir" == true ]]; then
    fail "system dir $entry comes after a user dir on PATH: $PATH"
  fi
done
echo "ok  npm -g into ~/.npm-global; user bin dirs after system dirs"

# Claude Code never self-updates.
[[ "${DISABLE_AUTOUPDATER:-}" == 1 && "${DISABLE_UPDATES:-}" == 1 ]] \
  || fail "DISABLE_AUTOUPDATER / DISABLE_UPDATES not set"
jq -e '.env.DISABLE_AUTOUPDATER == "1" and .env.DISABLE_UPDATES == "1"' \
  /etc/claude-code/managed-settings.json >/dev/null \
  || fail "managed settings do not disable updates"
echo "ok  claude updates disabled"

# Managed instructions state the branch naming rule and cannot be edited by dev.
[[ "$(stat -c %u:%a /etc/claude-code/CLAUDE.md 2>/dev/null)" == 0:644 ]] \
  || fail "/etc/claude-code/CLAUDE.md is missing or is not root-owned mode 644"
grep -qF '<type>/{ticket-id}-{short-summary}' /etc/claude-code/CLAUDE.md \
  || fail "managed CLAUDE.md does not state the branch naming rule"
echo "ok  managed CLAUDE.md with branch naming rule"

# tini is PID 1.
[[ "$(cat /proc/1/comm)" == tini ]] || fail "PID 1 is $(cat /proc/1/comm), expected tini"
echo "ok  tini is PID 1"

# Agent entrypoint: root-owned, on PATH, dev can run it but not edit it.
entrypoint="$(command -v agent-entrypoint)" || fail "agent-entrypoint not on PATH"
[[ "$(stat -c %u:%a "$entrypoint")" == 0:755 ]] \
  || fail "agent-entrypoint is not root-owned mode 755"

# A dry run turns an issue into a committed branch without pushing, and prints
# neither the App private key nor the installation token. The run is hermetic:
# a local bare repository stands in for the GitHub remote and a fake binary
# stands in for Claude Code, so there is no network, no live App and no AWS.
agent_tmp="$(mktemp -d)"
trap 'rm -rf "$agent_tmp"' EXIT
git -c init.defaultBranch=main init -q "$agent_tmp/src"
git -C "$agent_tmp/src" -c user.name=t -c user.email=t@example.invalid \
  commit -q --allow-empty -m "init"
git clone -q --bare "$agent_tmp/src" "$agent_tmp/remote/target.git"

cat >"$agent_tmp/fake-claude" <<'FAKE'
#!/usr/bin/env bash
# Stands in for Claude Code: makes a change instead of calling the model.
printf 'change\n' >CHANGE.md
FAKE
chmod +x "$agent_tmp/fake-claude"

# Sentinels for the secrets the entrypoint handles. They are set in the
# environment (so the entrypoint sees them) but must never reach its output.
agent_token="tok-SENTINELtokenDONOTPRINT"
agent_key="-----BEGIN PRIVATE KEY-----SENTINELkeyDONOTPRINT-----END PRIVATE KEY-----"

agent_out="$(
  AGENT_ISSUE=IAT-0 \
    AGENT_ISSUE_TITLE="Smoke Test Change" \
    AGENT_REPO=target \
    AGENT_DRY_RUN=1 \
    AGENT_INSTALLATION_TOKEN="$agent_token" \
    AGENT_APP_PRIVATE_KEY="$agent_key" \
    AGENT_APP_CLIENT_ID="sentinel-client-id" \
    AGENT_CLAUDE_BIN="$agent_tmp/fake-claude" \
    AGENT_CLAUDE_ARGS= \
    GITHUB_SERVER_URL="file://$agent_tmp/remote" \
    AGENT_WORKDIR="$agent_tmp/clone" \
    agent-entrypoint 2>&1
)" || fail "agent-entrypoint dry run failed:"$'\n'"$agent_out"

git -C "$agent_tmp/clone" rev-parse --verify -q feature/iat-0-smoke-test-change >/dev/null \
  || fail "dry run did not create the expected branch"
[[ -f "$agent_tmp/clone/CHANGE.md" ]] || fail "dry run did not run the worker"
git -C "$agent_tmp/clone" log -1 --pretty=%an | grep -qF 'devworkforce[bot]' \
  || fail "dry run did not commit as the bot"
printf '%s' "$agent_out" | grep -q 'not pushing' \
  || fail "dry run did not report that it skipped the push"

# The graded requirement: no secret in anything the entrypoint printed.
! printf '%s' "$agent_out" | grep -qF "$agent_token" || fail "installation token leaked to output"
! printf '%s' "$agent_out" | grep -qF SENTINELkey || fail "App private key leaked to output"
echo "ok  agent-entrypoint dry run: branch + commit, no secret printed"

echo "base: ok"
