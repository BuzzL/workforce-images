# Agent GitHub App key: setup and rotation runbook

The `buzzl-workforce-agent` GitHub App key is used by `Bump pins` (this repo) and `release-please` (`workforce-testbed`). It is an **environment secret** of the GitHub Environment `agent-app`, limited to `main`, so workflows on PR branches cannot read it. There is no repo-level copy. Permissions and storage plan: `workforce-testbed/CLAUDE.md` (section "GitHub App").

Run everything with the maintainer's `gh` login. Never print the key: it is piped from the file. `KEY_FILE` is the local `.pem` (outside every repo) and `CLIENT_ID` the App's client ID (not secret).

```sh
KEY_FILE=/path/to/private-key.pem
CLIENT_ID=<app client id>
```

Until step 5 is done, a repo-level copy of the key still exists and any same-repo PR workflow can read it. `scripts/check_app_key_env.py` is a lint against accidental regressions, not enforcement: the branch policy and maintainer review of workflow changes are the controls.

## 1. Create the environment (per repo)

Run for `workforce-images` and `workforce-testbed`. The `PUT` is idempotent but resets protection rules, so re-run it only if you have added none. The branch policy is created only when missing.

```sh
for R in workforce-images workforce-testbed; do
  gh api -X PUT "repos/BuzzL/$R/environments/agent-app" \
    -F 'deployment_branch_policy[protected_branches]=false' \
    -F 'deployment_branch_policy[custom_branch_policies]=true'
  gh api "repos/BuzzL/$R/environments/agent-app/deployment-branch-policies" --jq '.branch_policies[].name' | grep -qx main ||
    gh api -X POST "repos/BuzzL/$R/environments/agent-app/deployment-branch-policies" -f name=main -f type=branch
done
```

No required reviewers: the jobs must run unattended (weekly bumps, releases on push to `main`). The `main`-only branch policy is what keeps PR workflows out.

## 2. Add the secret and the variable

```sh
for R in workforce-images workforce-testbed; do
  gh secret set AGENT_APP_PRIVATE_KEY --env agent-app -R "BuzzL/$R" < "$KEY_FILE"
  gh variable set AGENT_APP_CLIENT_ID --env agent-app -R "BuzzL/$R" --body "$CLIENT_ID"
done
```

## 3. Verify the environment

```sh
for R in workforce-images workforce-testbed; do
  echo "== $R"
  gh api "repos/BuzzL/$R/environments/agent-app/deployment-branch-policies" --jq '.branch_policies[].name'   # main
  gh api "repos/BuzzL/$R/environments/agent-app" --jq '[.protection_rules[]?.type] | index("required_reviewers") | not'   # true
  gh secret list --env agent-app -R "BuzzL/$R"                                                                # AGENT_APP_PRIVATE_KEY
  gh variable list --env agent-app -R "BuzzL/$R"                                                              # AGENT_APP_CLIENT_ID
done
```

## 4. Merge the workflow PRs, then prove they work

Only after the environment exists (a job naming a missing environment creates it empty and then has no key).

Negative test first, from the PR branch: the branch policy must refuse it.

```sh
gh workflow run bump-pins.yml -R BuzzL/workforce-images --ref <pr-branch>
gh run list -R BuzzL/workforce-images --workflow bump-pins.yml --limit 1   # fails: branch not allowed by the environment
```

After merging both PRs, on `main`. This opens real bump PRs if newer tool versions exist (review or close them):

```sh
gh workflow run bump-pins.yml -R BuzzL/workforce-images
sleep 5; gh run watch -R BuzzL/workforce-images --exit-status "$(gh run list -R BuzzL/workforce-images --workflow bump-pins.yml --limit 1 --json databaseId --jq '.[0].databaseId')"
gh run list -R BuzzL/workforce-testbed --workflow release.yml --limit 1 --json headSha,conclusion   # the run for the merge commit (compare headSha with `git rev-parse origin/main`) succeeded
```

## 5. Delete the repo-level secret, one repo at a time

Only after step 4 succeeded for that repo.

```sh
R=workforce-images   # then workforce-testbed
gh secret delete AGENT_APP_PRIVATE_KEY -R "BuzzL/$R"
gh secret list -R "BuzzL/$R"   # must not list AGENT_APP_PRIVATE_KEY
```

Then re-run step 4 once more to confirm the environment secret alone is enough. The old key was readable by PR workflows until now: rotate it once (below).

## Rotation and the move to Secrets Manager (M4)

1. In the App settings, generate a new private key, update the environment secret (step 2), run step 4, then delete the old key in the App settings.
2. At M4 the key moves to Secrets Manager in the `workforce` account for the ECS agent tasks. Remove the GitHub copies only when nothing in GitHub Actions needs the App any more, and rotate the key at the move.
