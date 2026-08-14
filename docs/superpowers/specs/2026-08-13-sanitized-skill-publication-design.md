# Sanitized Skill Publication Design

## Goal

Publish every recoverable user-maintained Codex skill to the public
`reddydamodar38/claude-skills` repository without publishing credentials,
generated run artifacts, caches, nested Git metadata, or files rejected by
GitHub's 100 MB file limit.

## Source and layout

- Synchronize accessible directories from `C:\Users\DP096786\.codex\skills`.
- Exclude Codex's built-in `.system` directory and backup directories.
- Add `app-tier-scp-investigator` from the user-provided network location.
- Preserve the repository's existing `codex-skills/<skill-name>` collection.
- Refresh existing legacy top-level skill copies from their sanitized
  `codex-skills` equivalents so the public tree has no conflicting copies.
- Record but do not invent content for broken junctions whose targets no longer
  exist.

## Sanitization

- Replace embedded passwords and connection details with named environment
  variables or explicit runtime inputs.
- Preserve the scripts' existing execution flow and fail clearly when a
  required variable is absent.
- Reject private-key blocks, common access-token prefixes, literal credential
  assignments, generated output directories, caches, nested `.git`
  directories, and files larger than 100 MB.
- Exclude generated reports and local build-work directories from the
  publication tree.

## Validation

- Require a valid `SKILL.md` in each published skill directory.
- Parse PowerShell scripts to catch syntax errors after credential changes.
- Run existing non-destructive tests where available and practical.
- Run a repository-wide publication scan before commit and again before push.
- Review the staged diff, commit on a dedicated branch, and push that branch.

## Delivery

Push `codex/sanitize-and-sync-all-skills` and provide a GitHub compare/PR URL.
Do not write directly to `main`.
