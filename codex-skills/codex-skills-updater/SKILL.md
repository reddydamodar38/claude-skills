---
name: codex-skills-updater
description: Update and sync this `codex-skills` repository wherever it is installed for a user, then install newly added skills by creating missing symlinks into the Codex skills directory. Use when users ask to refresh local skill installs, pull latest repo changes, fix stale links, or sync new skill folders on Linux or Windows.
---

# Codex Skills Updater

Update an existing local clone of `codex-skills` and sync any new skill folders into Codex's discovered skills directory.

## Workflow

1. Detect OS and shell:
- Linux/macOS: use `scripts/sync_codex_skills.sh`
- Windows/PowerShell: use `scripts/sync_codex_skills.ps1`
2. Resolve repo path:
- use user-provided path first
- if missing, auto-discover likely `codex-skills` clones under the user home directory
- if multiple are found, pick the most recently modified and report the choice
3. Resolve Codex skills directory:
- use `CODEX_HOME` when set
- otherwise default to `~/.codex/skills`
4. Update repository:
- if working tree is clean, run fetch + fast-forward pull
- if dirty, do not pull; report why and continue with link sync
- optional: allow autostash pull mode to stash local changes, run ff-only pull, then re-apply stash
- if stash re-apply conflicts, print step-by-step conflict resolution guidance
5. Sync skill links:
- for each top-level folder containing `SKILL.md`, ensure a symlink exists in Codex skills directory
- never overwrite a real directory/file at destination
- if destination is a symlink to a different target, refresh only when requested
6. Verify and summarize:
- list installed/synced skills
- call out warnings (permission issues, non-link collisions, stale links)

## Commands

Linux/macOS:

```bash
bash scripts/sync_codex_skills.sh
bash scripts/sync_codex_skills.sh --refresh-links
bash scripts/sync_codex_skills.sh --autostash-pull
bash scripts/sync_codex_skills.sh --repo ~/git/codex-skills --skills-dir ~/.codex/skills
```

Windows (PowerShell):

```powershell
pwsh -File .\scripts\sync_codex_skills.ps1
pwsh -File .\scripts\sync_codex_skills.ps1 -RefreshLinks
pwsh -File .\scripts\sync_codex_skills.ps1 -AutostashPull
pwsh -File .\scripts\sync_codex_skills.ps1 -RepoPath "$HOME\git\codex-skills" -SkillsDir "$HOME\.codex\skills"
```

## Guardrails

- Avoid destructive actions.
- Never remove non-symlink destinations automatically.
- Explain any manual cleanup needed before retrying link creation.
- If symlink creation fails on Windows, suggest enabling Developer Mode or running an elevated shell.
