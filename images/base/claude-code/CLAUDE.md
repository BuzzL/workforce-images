# Conventions baked into the workforce base image

## Branches

Name every branch `feature/{ticket-id}-{short-summary}`:

- `{ticket-id}` is the Linear issue key, as written in Linear (e.g. `IAT-22`).
- `{short-summary}` is a few lowercase, hyphen-separated words describing the change.
- Example: `feature/IAT-22-publish-images-ghcr`.

Use this instead of the branch name Linear suggests. Create the branch from an up-to-date `main`.
