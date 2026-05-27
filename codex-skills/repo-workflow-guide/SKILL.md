---
name: repo-workflow-guide
description: Guide repo contribution workflows for Abilities Center tools, including repo setup, repo access, git and gh checks, branch hygiene, commit and push flow, PR creation, and repo-specific release or changelog checks. Use when the user or another skill needs help making changes to a repo rather than just reading or running it.
---

# Repo Workflow Guide

Use this skill when the task is about changing a repo and getting that change upstream.
This includes setup, branch selection, commit and push flow, PR creation, and release-oriented checks.

Keep the main flow small. Read only the reference file needed for the current step.

## Workflow

1. Classify the request before reading deeply:
- repo access or tooling setup
- sync or branch hygiene
- commit and push workflow
- PR creation or PR cleanup
- release or release-readiness question
2. Read `references/repo-access.md` first when the repo is missing locally, enterprise access is unclear, or the user may need setup help before changing anything.
3. Check repo-local instructions before applying generic guidance:
- `CONTRIBUTING.md`
- `README.md`
- release docs
- changelog or version files
- PR templates under `.github/`
4. Read only one or two additional references that match the question:
- `references/repo-access.md` for local clone checks, enterprise access setup, and targeted repo inspection paths
- `references/auth-and-tools.md` for `git`, `gh`, enterprise GitHub, VPN, and SSH-key setup details
- `references/change-workflow.md` for branch, commit, push, and PR flow
- `references/release-checks.md` for release-oriented questions, version bumps, changelog checks, and repo-specific release verification
5. Prefer repo-specific rules over generic rules when they conflict.
6. When machine-local `AGENTS.md` guidance is available, treat it as the first place to look for local clone roots, auth preferences, and tool-availability defaults.
7. If those machine-local facts are repeatedly discovered and are stable, non-sensitive, and likely to help future tasks, suggest adding them to local `AGENTS.md` and point to `abilities-center-guide/references/local-agents-guidance.md` for what belongs there.
8. If the ask is broader than repo contribution flow itself, route back to `abilities-center-guide`.

## Guardrails

- Do not plan direct commits to `main` or `master` as the normal workflow, even if protections are missing or bypass is technically possible.
- Do not assume every repo uses the same default branch, PR template, changelog format, or release process.
- Do not overwrite or discard user work to make the repo "clean" without explicit approval.
- Prefer SSH-based auth for normal enterprise GitHub clone, push, and PR workflows when the user needs durable access.
- Treat machine-local `AGENTS.md` defaults as local to that machine. Do not project them onto other users, machines, or non-lab repos without checking.
- If `gh` is unavailable, unauthenticated, or unsupported in the current environment, fall back to `git push` plus manual PR URLs or repo web instructions.
- If the repo has local changes, divergence, or a non-default branch, explain the tradeoff before forcing sync.

## Response Style

- Start with the next concrete step.
- Name the repo-specific file or check that governs the workflow when one exists.
- Show the safest sequence for branch, commit, push, and PR steps.
- If the repo lacks explicit contribution docs, prefer a conservative branch -> PR -> review -> merge -> release flow rather than inventing a direct-push shortcut.
- If release behavior is unclear, say what artifact should confirm it instead of guessing.

## Reference Loading Guide

- Need repo access, clone state, or enterprise access setup: read `references/repo-access.md`
- Need enterprise GitHub auth/tool checks: read `references/auth-and-tools.md`
- Need branch, commit, push, or PR workflow: read `references/change-workflow.md`
- Need release or versioning guidance: read `references/release-checks.md`
