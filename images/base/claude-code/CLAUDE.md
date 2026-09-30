# Conventions baked into the workforce base image

## Branches

Name every branch you create `<type>/{ticket-id}-{short-summary}`, following [Conventional Branch](https://conventionalbranch.org/):

- `<type>` comes from the Linear issue's label: `Feature` and `Improvement` give `feature/`, `Bug` gives `bugfix/`. Use `hotfix/`, `release/` or `chore/` only when the issue says so. If the issue has no label, ask which type to use.
- `{ticket-id}` is the Linear issue key in lowercase (e.g. `iat-22`). If the work has no ticket, ask which one to use.
- `{short-summary}` is a few words describing the change.
- The whole description uses only lowercase letters, digits and single hyphens: no uppercase, spaces, underscores, dots or consecutive, leading or trailing hyphens.
- Example: `feature/iat-22-publish-images-ghcr`.

Use this instead of the branch name Linear suggests, and create the branch from an up-to-date default branch. Existing branches keep their names (e.g. `deps/<tool>-<version>` from the pin-bump workflow).
