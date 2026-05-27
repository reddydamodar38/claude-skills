# Documentation Sources

Use this file when the question is primarily about where Abilities Center documentation should live or which shared documentation source to check next.

## Shared Docs First

For shared Abilities Center process and guidance questions, prefer the shared documentation repo:
- `abilities-center/.github-private`

Use it for:
- shared process notes
- links to tool-specific repos
- ownership or maintainer clues
- cross-tool documentation that does not belong in a single code repo

## Still Verify in Code

Even when `.github-private` has the best narrative documentation, verify these in active repos or automation before answering as fact:
- run commands
- environment selection
- credentials or auth patterns
- supported execution paths
- exact file locations

## Search Order for Documentation Questions

1. active repo docs closest to the tool or workflow
2. shared docs in `abilities-center/.github-private`
3. runbooks linked from those repos
4. issue or PR history when the docs and code disagree

## What to Ask For If Missing

If `.github-private` is not in the current workspace and the user wants help from it, ask for one of:
- a local clone path
- the repo section or file path to inspect
- the exact doc title
- the repo URL if access needs to be set up
