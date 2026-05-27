# Auth And Tools

Use this file when the user needs help getting to a state where repo changes can be cloned, committed, pushed, or reviewed.

If the question starts one level earlier, such as "is the repo cloned?" or "should I use `gh` or clone?", read `references/repo-access.md` first.

## Preflight

Before planning repo changes, verify:
- network reachability to `github.cerner.com`
- the user is on the Abilities Lab VPN or already inside the DH2 or OCI network when required
- `git` is installed for clone, branch, commit, and push flow
- `gh` is installed only if the workflow will use GitHub CLI features such as PR creation or repo inspection

Do not treat repo access as broken until VPN, enterprise reachability, and tool availability have been checked.

## Auth Guidance

For enterprise GitHub workflows here:
- prefer SSH key setup when the user needs normal day-to-day clone, commit, push, and PR work
- do not assume public GitHub-style browser SSO is available
- if `gh` is used, verify auth to `github.cerner.com` separately from `git` auth

Possible auth shapes:
- `git` over SSH for clone, fetch, pull, push
- `gh` auth for PR creation or targeted repo inspection
- manual web PR creation when `gh` is unavailable or blocked

## Existing Clone Checks

If the repo already exists locally, check:
- current branch
- remote URL
- default branch name such as `main` or `master`
- whether the clone is behind origin
- whether the working tree has tracked or untracked changes

If the repo is not current, explain the choice:
- continue with stale local context
- sync first
- create a fresh clone elsewhere

## Setup Outcomes

If setup is blocked, answer with:

1. which prerequisite is missing
2. whether it is VPN, enterprise auth, `git`, `gh`, or SSH-key related
3. the next exact command or manual action needed
