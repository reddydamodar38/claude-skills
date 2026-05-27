# Local AGENTS Guidance

Use this file when the question is about what should live in a machine-local `AGENTS.md`, how skills should use that information, or how to separate local defaults from Abilities Center-specific guidance.

## Purpose

A machine-local `AGENTS.md` is a good place for durable local defaults that many skills can reuse without rediscovering them every time.

Good examples:
- where the user usually stores repos
- whether `git` is already installed and working
- whether `gh` is already installed and working
- whether SSH is the preferred GitHub auth path on that machine
- the first clone root to check when a repo path is unknown

## What Belongs There

Put these kinds of facts in local `AGENTS.md`:
- machine-local tool availability
- machine-local auth preferences such as SSH for `github.cerner.com`
- common local clone roots such as `~/git`
- stable workflow defaults that apply to most work on that machine

Keep it short and durable.

## What Does Not Belong There

Avoid putting these in machine-local `AGENTS.md`:
- secrets, tokens, passwords, or private keys
- long tool documentation
- fast-changing environment facts
- repo-specific release procedures
- instructions that only apply inside one repo

Those belong in skills, repo `AGENTS.md`, or repo-local docs instead.

## General vs Lab-Specific Defaults

Some defaults may be broadly local:
- `git` works
- `gh` works
- most repos live under `~/git`

Some defaults may be Abilities Center or lab-specific:
- prefer SSH for `github.cerner.com`
- many Abilities Center repos live on enterprise GitHub
- lab-related repos are often cloned under the same root

When writing local defaults, make that distinction explicit so non-lab tasks are not forced into lab-only assumptions.

For example, prefer wording like:
- "For `github.cerner.com`, prefer SSH"
- "For Abilities Center repos, check `~/git/<repo-name>` first"

instead of claiming those rules apply to every repo everywhere.

## How Skills Should Use It

Repo-aware skills should treat machine-local `AGENTS.md` entries as local defaults:
- use them first when choosing where to look for clones
- use them first when deciding whether SSH or `gh` is likely already set up
- still verify when the task is high-risk or the local default may not apply

If a repo-local `AGENTS.md` or repo docs conflict with machine-local defaults, the more specific repo-local guidance wins.

If a skill keeps rediscovering the same machine-local facts and those facts are:
- stable
- non-sensitive
- likely to help future tasks

then it should suggest capturing them in machine-local `AGENTS.md`.

## Recommended Pattern

Use a short structure like:

1. local tool availability
2. local repo storage conventions
3. enterprise GitHub or lab-specific notes
4. safety note that these are local defaults, not universal rules
