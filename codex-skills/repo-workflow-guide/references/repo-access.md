# Repo Access

Use this file when the answer depends on reading a repo, but the repo may or may not already exist locally and the user's machine may not be set up yet.

Keep this generic. Do not assume:
- the repo is already cloned
- `gh` is installed
- `git` is installed
- the user is already on VPN or inside the Abilities Center network
- the current machine layout matches your own

If machine-local `AGENTS.md` guidance exists, use it as the first source for local clone roots, auth preferences, and tool-availability defaults. Still treat those as machine-local assumptions rather than universal rules.

## Access Preconditions

Most Abilities Center repos live in the `github.cerner.com` enterprise instance.

Before using `gh` or cloning, verify access basics:
- network reachability to `github.cerner.com`
- user is on the Abilities Lab VPN or already inside the DH2 or OCI network
- required tooling exists for the chosen path:
  - `gh` for targeted API-backed inspection
  - `git` for clone, fetch, pull, branch, commit, and push flows

If the user is not set up yet, help them get to a working access state before treating the repo as unavailable.

## Preferred Access Order

1. Existing local clone
2. Targeted remote read with `gh`
3. Fresh local clone for deeper investigation

Pick the lightest option that can still answer the question confidently.

## Existing Local Clone First

Find or ask whether the repo already exists locally.

Check for:
- a user-provided repo path
- a nearby clone in the user's usual git workspace
- sibling repos that commonly live beside the current repo
- clone-root hints from machine-local `AGENTS.md`, such as `~/git`

If a local clone exists, prefer it because it is faster to search and better for cross-file understanding.

## If the Repo Already Exists

Before relying on an existing clone, verify how current it is.

Check:
- current branch
- remote tracking branch
- whether the default branch is `main` or `master`
- whether the clone is behind origin
- whether the working tree has tracked or untracked changes

Prefer to work from the latest `origin/main` or `origin/master`, but do not force cleanup or branch changes if the user wants to keep local differences.

If the clone is not current, explain the tradeoff plainly:
- continue with the existing clone and accept stale context risk
- update the clone first
- use a fresh clone elsewhere

Untracked files or local changes are allowed as long as the user understands the clone may not reflect current upstream behavior.

## Targeted Remote Read With `gh`

Use `gh` when:
- you need a small number of files
- you need to confirm whether a repo or path exists
- you need to inspect repo metadata, default branch, or contents
- cloning would be unnecessary overhead

Good fits for `gh`:
- reading a `README`
- listing top-level directories
- fetching one or two known file paths
- checking repo existence or ownership in the org

Before using `gh`, verify:
- `gh` is installed
- the user can authenticate to `github.cerner.com`
- enterprise network access works

If the current environment restricts auth-backed commands, elevated permissions may be required for `gh`.

## Fresh Clone When Depth Matters

Clone when:
- the question needs broad code understanding across many files
- you need to search implementation details, templates, or defaults
- you expect repeated follow-up questions about the same repo
- a sibling skill will likely need ongoing local access

Before cloning, verify:
- `git` is installed
- access to `github.cerner.com` works
- the user has a supported auth path for clone and later push operations

For enterprise GitHub here, prefer SSH key setup when the user will need normal repo workflows such as clone, commit, and push. This instance may not support the same SSO/browser login path a public GitHub flow would.

When cloning, suggest the user's normal git workspace such as `<user-home>/git`, but do not require a specific directory. Keep the chosen repo path explicit in the answer so future turns can reuse it.

## Guidance for Other Skills

For tool-specific skills such as `torq-toolbelt` or `node-orchestration-runner`:
- use the local clone if present
- otherwise use `gh` for narrow inspection
- clone only when troubleshooting or implementation depth requires it
- if access/setup is the blocker, help the user verify VPN, tooling, and enterprise auth first

Do not assume another user will have the same clone layout or local tools as the current workspace.

## Output Pattern

When repo access is part of the answer, say:

1. which repo you checked or want to check
2. whether the answer came from a local clone, `gh`, or a fresh clone
3. whether access setup, VPN, enterprise auth, or tool installation is the blocker
4. whether deeper validation would benefit from cloning
