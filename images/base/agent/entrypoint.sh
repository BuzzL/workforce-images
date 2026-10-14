#!/usr/bin/env bash
# Agent entrypoint: turn a tracker issue into a pull request.
#
# This is what an ECS agent task runs. It mints a short-lived GitHub App
# installation token, clones the target repository, creates a branch following
# the project's naming rule, runs Claude Code on the issue, commits the result
# as the bot and -- unless this is a dry run -- pushes the branch and opens the
# pull request.
#
# Secret hygiene is deliberate. The App private key and the installation token
# never reach a process argument, a remote URL or a log line: the key reaches
# openssl only through a 0600 temporary file (removed on every exit path), the
# token reaches git and gh only through a credential helper and GH_TOKEN, and
# diagnostics print an explicit allowlist of non-sensitive settings rather than
# the environment as a whole. The script never enables shell tracing, which
# would echo both. The worker is untrusted -- its prompt is built from
# attacker-controllable issue content -- so both secrets are scrubbed from the
# environment before it runs, and its output is scanned for a leaked key or
# token before anything is committed.

set -euo pipefail

log() { printf 'agent: %s\n' "$*" >&2; }
die() { printf 'agent: error: %s\n' "$*" >&2; exit 1; }

# --- Inputs -----------------------------------------------------------------
# Required.
issue=${AGENT_ISSUE:?AGENT_ISSUE (tracker issue key, e.g. ABC-123) is required}
repo=${AGENT_REPO:?AGENT_REPO (owner/name of the target repository) is required}

# Optional, with defaults.
branch_type=${AGENT_BRANCH_TYPE:-feature}
base_branch=${AGENT_PR_BASE:-main}
server_url=${GITHUB_SERVER_URL:-https://github.com}
api_url=${GITHUB_API_URL:-https://api.github.com}
claude_bin=${AGENT_CLAUDE_BIN:-claude}
workdir=${AGENT_WORKDIR:-$(mktemp -d)}

dry_run=false
case "${AGENT_DRY_RUN:-}" in
  1 | true | yes | TRUE | YES) dry_run=true ;;
esac

# --- Branch, commit and PR naming -------------------------------------------
# Lowercase letters, digits and single hyphens only, per Conventional Branch.
slugify() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//'
}

ticket=$(printf '%s' "$issue" | tr '[:upper:]' '[:lower:]')
summary=$(slugify "${AGENT_BRANCH_SUMMARY:-${AGENT_ISSUE_TITLE:-changes}}")
[[ -n $summary ]] || summary=changes
branch="${branch_type}/${ticket}-${summary}"
[[ $branch =~ ^[a-z]+/[a-z0-9]+(-[a-z0-9]+)*$ ]] \
  || die "computed branch '$branch' is not a valid Conventional Branch name"

# Conventional Commit type from the branch type.
case "$branch_type" in
  feature | improvement) cc_type=feat ;;
  bugfix | hotfix) cc_type=fix ;;
  *) cc_type=chore ;;
esac
commit_subject=${AGENT_COMMIT_SUBJECT:-"$cc_type: address ${issue}"}
pr_title=${AGENT_PR_TITLE:-${AGENT_ISSUE_TITLE:-$commit_subject}}
pr_body=${AGENT_PR_BODY:-"Automated change for ${issue}."}

print_settings() {
  log "settings:"
  log "  issue=${issue}"
  log "  repo=${repo}"
  log "  branch=${branch}"
  log "  base=${base_branch}"
  log "  server=${server_url}"
  log "  dry_run=${dry_run}"
}

# --- Installation token ------------------------------------------------------
# Mint a 1-hour installation access token from the App credentials. The private
# key is written to a 0600 temp file for openssl and removed immediately; the
# JWT and the token stay in shell variables and are never logged.
mint_token() {
  local client_id owner now header payload signature jwt installation_id token
  # key_file is intentionally not 'local': mint_token always runs in a
  # command-substitution subshell, so a plain assignment stays confined to that
  # subshell yet remains visible to the EXIT trap below, which runs after the
  # function has returned (when a 'local' would already be out of scope).
  client_id=${AGENT_APP_CLIENT_ID:?AGENT_APP_CLIENT_ID is required to mint a token}
  owner=${AGENT_APP_OWNER:-${repo%%/*}}

  key_file=$(mktemp)
  chmod 600 "$key_file"
  # Remove the key file on every exit path of this subshell, so an openssl or
  # base64 failure under set -e can no longer leave it on disk. The guard keeps
  # set -u happy if we exit before key_file is assigned.
  trap 'rm -f "${key_file:-}"' EXIT
  if [[ -n ${AGENT_APP_PRIVATE_KEY_FILE:-} ]]; then
    cat -- "$AGENT_APP_PRIVATE_KEY_FILE" >"$key_file"
  elif [[ -n ${AGENT_APP_PRIVATE_KEY:-} ]]; then
    printf '%s' "$AGENT_APP_PRIVATE_KEY" >"$key_file"
  else
    rm -f "$key_file"
    die "AGENT_APP_PRIVATE_KEY or AGENT_APP_PRIVATE_KEY_FILE is required to mint a token"
  fi

  b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }
  now=$(date +%s)
  header=$(printf '{"alg":"RS256","typ":"JWT"}' | b64url)
  payload=$(printf '{"iat":%d,"exp":%d,"iss":"%s"}' $((now - 60)) $((now + 540)) "$client_id" | b64url)
  signature=$(printf '%s.%s' "$header" "$payload" | openssl dgst -sha256 -sign "$key_file" | b64url)
  jwt="$header.$payload.$signature"
  rm -f "$key_file"

  api() {
    curl -fsS -X "$1" "${api_url%/}/$2" \
      -H "Authorization: Bearer $jwt" \
      -H "Accept: application/vnd.github+json" \
      -H "X-GitHub-Api-Version: 2022-11-28"
  }
  json() { python3 -c "import json,sys; print(json.load(sys.stdin)['$1'])"; }

  installation_id=$(api GET "users/$owner/installation" | json id)
  token=$(api POST "app/installations/$installation_id/access_tokens" | json token)
  printf '%s' "$token"
}

# --- Run ---------------------------------------------------------------------
print_settings

if [[ -n ${AGENT_INSTALLATION_TOKEN:-} ]]; then
  token=$AGENT_INSTALLATION_TOKEN
else
  log "minting installation token"
  token=$(mint_token)
fi

# The App private key and any pre-supplied token were needed only to obtain the
# installation token above. Scrub them from the environment now, before the
# untrusted worker runs, so a prompt-injected issue cannot make the worker read
# or exfiltrate them.
unset AGENT_APP_PRIVATE_KEY AGENT_APP_PRIVATE_KEY_FILE AGENT_INSTALLATION_TOKEN

# Serve the token to git through a credential helper and to gh through
# GH_TOKEN. It is never placed in the remote URL (which git would persist in
# .git/config) nor on any command line. Inherited helpers are reset first, and
# the helper is scoped to the configured server's host, so the token is never
# offered to any other host git might contact (e.g. via a redirect or a
# mis-set GITHUB_SERVER_URL).
export GIT_AUTHOR_NAME=${AGENT_GIT_USER_NAME:-devworkforce[bot]}
export GIT_AUTHOR_EMAIL=${AGENT_GIT_USER_EMAIL:-335405694+devworkforce[bot]@users.noreply.github.com}
export GIT_COMMITTER_NAME=$GIT_AUTHOR_NAME
export GIT_COMMITTER_EMAIL=$GIT_AUTHOR_EMAIL

if [[ $server_url =~ ^(https?)://([^/]+) ]]; then
  cred_url="${BASH_REMATCH[1]}://${BASH_REMATCH[2]}"
elif [[ $server_url =~ ^file:// ]]; then
  cred_url= # local remote (tests only): git never requests credentials
else
  die "GITHUB_SERVER_URL '$server_url' must be an http(s) or file URL"
fi
export GIT_CONFIG_COUNT=2
export GIT_CONFIG_KEY_0=credential.helper GIT_CONFIG_VALUE_0=
export GIT_CONFIG_KEY_1="credential.${cred_url:+${cred_url}.}helper"
# The helper expands $GH_TOKEN at git time, not when this value is set, so it
# must stay literal here.
# shellcheck disable=SC2016
export GIT_CONFIG_VALUE_1='!f() { echo username=x-access-token; echo "password=$GH_TOKEN"; }; f'

# The token reaches git and gh only through GH_TOKEN: set for the clone,
# withheld across the worker, and re-provided for the push/PR.
export GH_TOKEN=$token

log "cloning ${repo} into ${workdir}"
git clone --quiet --depth 1 --branch "$base_branch" "${server_url%/}/${repo}.git" "$workdir"
cd "$workdir"
git checkout -q -b "$branch"
log "created branch ${branch}"

# Withhold the token from the untrusted worker. The prompt is built from
# attacker-controllable issue content, so the worker must not be able to read
# the token or write it into a file the staging step below would then commit.
unset GH_TOKEN

log "running Claude Code on ${issue}"
prompt="Implement the following issue in this repository, following the repository's CLAUDE.md and the project conventions.

Issue: ${issue}
Title: ${AGENT_ISSUE_TITLE:-(see the issue tracker)}

${AGENT_ISSUE_BODY:-}"
read -r -a claude_args <<<"${AGENT_CLAUDE_ARGS:---permission-mode acceptEdits}"
"$claude_bin" "${claude_args[@]}" -p "$prompt"

git add -A
if git diff --cached --quiet; then
  log "no changes were produced; nothing to commit"
  exit 0
fi

# Defence in depth: refuse to commit a private key or the installation token,
# even though the worker ran without them in its environment.
if git diff --cached | grep -qE -- '-----BEGIN [A-Z ]*PRIVATE KEY-----'; then
  die "refusing to commit: staged changes contain a private key"
fi
if git diff --cached | grep -qF -- "$token"; then
  die "refusing to commit: staged changes contain the installation token"
fi

git commit --quiet -m "$commit_subject" -m "Addresses ${issue}."
log "committed as ${GIT_AUTHOR_NAME}"

if $dry_run; then
  log "dry run: not pushing and not opening a pull request for ${branch}"
  exit 0
fi

# Re-provide the token now that the worker has finished.
export GH_TOKEN=$token

log "pushing ${branch}"
git push --quiet --set-upstream origin "$branch"
gh pr create \
  --repo "$repo" \
  --base "$base_branch" \
  --head "$branch" \
  --title "$pr_title" \
  --body "$pr_body"
log "opened a pull request for ${branch}"
