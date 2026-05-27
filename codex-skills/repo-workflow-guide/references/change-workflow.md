# Change Workflow

Use this file when the user needs the standard flow for making and sending a repo change upstream.

## Preferred Order

1. confirm repo-local contribution rules
2. confirm current branch and remote state
3. create or choose the correct working branch
4. make the change
5. review diff and validate
6. commit with a clear scoped message
7. push branch to origin
8. create or update PR

For Abilities Center repos, the normal safe path is:

1. make updates on a branch
2. commit to that branch
3. push branch to the repo
4. create PR
5. get user approval or required review
6. merge PR and delete branch
7. create a release PR if the repo uses release-driven changelog/version flow
8. create release after the release PR is merged

## Repo-Local Rules First

Before giving generic git advice, check for:
- `CONTRIBUTING.md`
- `.github/pull_request_template.md`
- release docs
- changelog or versioning rules

If the repo defines its own workflow, follow that instead of a generic pattern.

For Abilities Center repos, `.github` templates and `CONTRIBUTING.md` are preferred sources for PR wording and checklist expectations.
If a repo has no explicit PR template, the `node-orchestration` pull request template is a good fallback pattern for Abilities Center-style PR structure.

## Branch Guidance

Prefer a dedicated branch for changes that should become a PR.
Do not treat direct commits to `main` or `master` as the default workflow, even when branch protections are absent or weak.
Prefer a branch in the actual repo over a personal fork when the user has normal branch access.

Check:
- current branch name
- whether it already tracks the intended remote branch
- whether it is safe to keep using that branch

If local unrelated changes exist, work with the user instead of discarding them.

Branch protection should be treated as a guardrail, not the reason for using branches. Even if a default branch is technically writable, prefer branch -> PR flow.

Using same-repo branches is encouraged because:
- it is easier for others with repo access to update or collaborate on the branch
- it avoids extra fork-sync overhead when the upstream default branch keeps moving

Fork-based flow is still allowed when needed, but should not be the first recommendation when normal repo branch workflow is available.

## Commit Guidance

Before committing:
- review `git status --short`
- review the diff or staged diff
- make sure the commit groups one coherent change

Commit messages should be:
- scoped to the change
- short but specific
- aligned with any repo-local conventions

When multiple unrelated PRs are being prepared, chore files such as `CHANGELOG.md` may be better handled in a separate PR if they would otherwise create avoidable review or merge friction.

For repos following release-driven changelog flow:
- do not add the final release version header in the work PR
- keep changelog-ready content in both the PR's top description or summary section and `CHANGELOG.md`
- use a shared pre-release-style changelog section until a later release PR assigns the final version heading
- include the PR link in that changelog-ready content when it is already known
- keep that changelog-ready content aligned with what the final changelog entry should eventually say
- let the later release PR assemble that content into the actual versioned changelog entry

Historical note:
- some repos or teams may still expect the older pattern of not touching `CHANGELOG.md` in the work PR
- if repo-local templates, `CONTRIBUTING.md`, or current team practice still say that, follow the repo-local rule instead of forcing the newer pre-release-section model

## Push Guidance

When pushing:
- push the working branch, not the default branch, unless the repo explicitly uses a direct-push workflow
- set upstream if needed
- confirm whether push succeeded before planning PR creation

If push is blocked by auth or permissions, surface that clearly and switch back to setup or access guidance.

## PR Guidance

Prefer GitHub CLI when available and authenticated.
If `gh` is unavailable or blocked, fall back to manual PR creation in the repo web UI.

PR guidance should include:
- base branch
- head branch
- summary of change
- risk or testing notes when appropriate
- any required reviewers, labels, or tracking fields if the repo expects them

For Abilities Center repos, a good default PR shape is:
- **Description of Changes**
- **Motivation and Context**
- **How was it tested?**
- **Type of Change**
- **Checklists**
- **Tracking**

That pattern matches the current `node-orchestration` PR template and is a reasonable fallback when a repo does not define its own template.

If a repo template says not to update `CHANGELOG.md` in the same PR, follow that template rather than forcing changelog edits into feature PRs.

When a repo uses a separate release PR:
- feature PRs should focus on the change itself
- feature PRs should make the top summary or description section match the intended changelog-ready content as closely as practical
- feature PRs should update `CHANGELOG.md` with that same changelog-ready content when the repo follows this model
- release PRs should handle final changelog versioning, release metadata, and release assembly

## Branch Protection Note

Do not assume GitHub branch protection can exempt specific files from pull-request rules on a protected branch.
If a team needs file-specific policy, look at repo rulesets, push rules, CODEOWNERS, or a separate chore PR strategy instead of assuming branch protection can carve out single-file exceptions.

## Output Pattern

When helping with a repo change, answer in this order:

1. current repo state that matters
2. next safe command or action
3. any repo-local file that should be checked
4. what remains after that step
