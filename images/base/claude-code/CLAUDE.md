# Conventions baked into the workforce base image

## Branches

Name every branch you create `feature/{ticket-id}-{short-summary}`:

- `{ticket-id}` is the Linear issue key, as written in Linear (e.g. `IAT-22`).
- `{short-summary}` is a few lowercase, hyphen-separated words describing the change.
- Example: `feature/IAT-22-publish-images-ghcr`.

Use this instead of the branch name Linear suggests, and create the branch from an up-to-date default branch. Existing branches keep their names (e.g. `deps/<tool>-<version>` from the pin-bump workflow). If the work has no ticket, ask which one to use before creating the branch.
