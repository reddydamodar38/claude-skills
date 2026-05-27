# Where to Look

Use this file when the user asks where something lives, where to verify it, or where to keep digging.

## Search Order

Search from the most execution-adjacent place outward:

1. Local repo files already in the workspace
2. Sibling skills in this repo when the topic matches a tool family
3. Repo-local configs, scripts, inventories, and templates
4. Shared documentation repos such as `abilities-center/.github-private`
5. Team-maintained docs or runbooks linked from active repos
6. People or teams, only after artifact-based discovery is exhausted

## Good Evidence by Question Type

For "how does it run now?":
- active scripts
- automation entrypoints
- inventory files
- compose files
- current examples

For "where is this documented?":
- repo `README`
- shared docs repos such as `abilities-center/.github-private`
- runbooks
- `references/` folders in skills
- workflow docs near the code

For "what environment or system is involved?":
- inventory files
- environment config
- compose or Terraform files
- connection aliases
- runner setup docs
- `references/lab-topology.md` for shared Abilities Center or Abilities Lab terminology and access patterns

For "where did the test output go?":
- shared test folder path
- host-named subfolders
- Jenkins-generated support folders
- archive zip or archive pointer files
- `references/test-data.md` for shared naming and layout conventions

For "who owns this?":
- repo org and commit history
- current maintainers in docs
- codeowners or review patterns
- shared docs repo ownership hints, but verify elsewhere when possible

## Search Patterns

Prefer fast targeted searches:

- file names with tool or environment names
- repo roots with `README`, `docs`, `references`, `runbook`, `inventory`, `compose`, `terraform`
- strings from the user's prompt: hostnames, env names, script names, aliases
- older naming such as `Abilities Lab`, `on-prem`, `DH2`, `abldev1`, `fedscale`, or `EOD`
- local skill names that match the domain
- shared docs repo names such as `.github-private`

## Shared Docs Usage Pattern

Use shared docs repos to gather:
- canonical doc locations
- current workflow names
- repo links
- owner names
- maintained process notes

Then verify execution-sensitive details in active code or automation before answering confidently.

When the question is about shared Abilities Center documentation, read `references/doc-sources.md`.
When the question is about reading a repo that may not be cloned locally, route to `repo-workflow-guide`.
When the question is about test-folder naming, artifact layout, or archive expectations, read `references/test-data.md`.

## Output Pattern

When answering a "where is it?" question, prefer this order:

1. most likely current location
2. one backup place to check
3. confidence note if the trail came from weak sources
