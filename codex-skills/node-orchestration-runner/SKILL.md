---
name: node-orchestration-runner
description: Choose and run the correct node-orchestration automation commands in this repo using docker-compose, ansible, and terraform. Use when the user asks to run, preview, or troubleshoot automation for `lab_inventory`, `oci_inventory`, or `abldev1_inventory`, including selecting environment inventory files, limiting scope (`-l`/`-t`), running scoped reruns, and handling Terraform create/destroy flows for specific nodes.
---

# Node Orchestration Runner

Run automation in `node-orchestration` (also called `TACO`) by choosing the correct inventory, scope, and execution mode.
Default to smallest safe scope first, then expand only when user asks.

Inventory intent map:
- `abldev1_inventory`: abldev1 OCI environments.
- `oci_inventory`: older fedscale OCI environments.
- `lab_inventory`: on-prem or DH2 environments.
- `vra8/`: EOD-only special flow, not a typical operator-run path.

## Workflow

1. Confirm the `node-orchestration` repo is available locally before planning execution:
- if the repo is missing, use the shared repo-access workflow from `repo-workflow-guide/references/repo-access.md`
- if local `AGENTS.md` guidance exists, use its machine-local clone-root and auth defaults first
- if those same stable machine-local defaults keep being rediscovered, suggest adding them to local `AGENTS.md`
- prefer an existing local clone first
- otherwise use targeted `gh` inspection only for narrow repo/path checks
- clone only when deeper repo access is required for execution or troubleshooting
2. Confirm repo root contains `docker-compose.yml`.
3. Confirm git branch and remote state before execution:
- fetch latest from origin
- check whether current branch is behind upstream
- if behind, pull/rebase before running automation (unless user explicitly asks not to)
- if skill work changes files, create/use a dedicated branch (not shared/main branch)
4. Confirm execution location is safe:
- run from a user-owned Linux runner (for example Linux secondary, including VS Code remote session)
- if session is on Windows, SSH to the user-owned Linux runner first, then run TACO there
- do not run from shared jump boxes/hosts where OCI auth would be shared across users
5. Verify Docker readiness before TACO commands:
- `docker compose version` (or `docker-compose version`) works
- current user can run docker commands
- if Docker is missing/not usable, use `docker-runner-setup` skill to install/repair and validate host readiness before attempting automation
6. For `abldev1_inventory` and `oci_inventory`, run OCI auth preflight before any playbook/Terraform command:
- verify repo-level auth folder exists: `oci_api/`
- verify config exists: `oci_api/config`
- verify at least one private key file exists under `oci_api/*.pem`
- verify compose mount pattern in `docker-compose.yml` maps `./oci_api` to `/root/.oci` (current standard mode)
- verify profiles in `oci_api/config`:
  - required for abldev1: `abldev1` (or value from `abldev1_inventory/group_vars/all.yml: config_profile_name`)
  - required for `oci_inventory` (fedscale): `fedscale`
  - allow user-defined `DEFAULT` value; do not overwrite `DEFAULT` unless explicitly requested
- verify selected profile has `key_file=/root/.oci/...` in current `oci_api` mode
- if future mode is detected (auth read from `$HOME/.oci/config` instead of repo `oci_api`), validate that path instead of forcing migration back
7. Confirm requested mode:
- Ansible run
- Terraform run
- Container shell only
8. Ask only for run-critical missing inputs:
- inventory family (`lab_inventory`, `oci_inventory`, `abldev1_inventory`)
- env name
- scope (`-l` host/group, optional `-t` tags)
- read-only vs apply
9. Prefer direct containerized commands from repo root:
- `docker-compose run --rm taco <command>`
- use `docker-compose run --rm taco bash` only when user asks for an interactive shell
10. Gate Terraform usage:
- run Terraform only for `abldev1_inventory` flows
- skip Terraform for `lab_inventory` and `oci_inventory`
11. For node provisioning or teardown, require explicit node target and run a scoped plan before apply/destroy.
12. Before destructive actions (destroy), confirm intent explicitly.
13. If changes were made in repo files:
- commit on dedicated branch with clear message
- push branch to origin
- create PR with summary of change, risk, and validation steps
14. For contribution-oriented asks (branch cleanup, PR prep, repo contribution conventions), check `CONTRIBUTING.md` at repo root and follow it unless user explicitly overrides.
15. Route back to `abilities-center-guide` when the question is broader than TACO execution itself, especially for shared environment naming, test-data conventions, repo discovery, or cross-tool workflow questions.

## Change Hygiene and PR Workflow

Use this when the user asks to clean up mixed local changes into separate branches/PRs.

1. Audit and preserve work:
- run `git status --short` and `git diff --stat`
- if working tree has mixed changes, create a safety stash first (`git stash push -u -m "<message>"`)
- keep the stash until user confirms cleanup is complete
2. Group related changes into focused branches:
- create each branch from `origin/master` (or the repo default branch)
- restore only the relevant files per branch from stash (`git checkout stash@{0} -- <files>`)
- commit with scoped message and push with upstream (`git push -u origin <branch>`)
3. PR creation:
- prefer `gh pr create -R <host/org/repo> -B master -H <branch>`
- do not use `--hostname` on `gh pr list/create` subcommands; use `-R` instead
- if `gh` is unavailable or unauthenticated, provide compare/new-PR URLs for manual creation
4. PR body formatting:
- if `.github/pull_request_template.md` exists, use it
- write **Description of Changes** in the same concise style as `CHANGELOG.md`:
  - top-level component scope (for example `OCI Inventory (fedscale):`)
  - short sub-bullets of concrete file/behavior changes
- include risk and validation details in template sections (`Motivation and Context`, `How was it tested?`)
- if user has no JIRA, set `Tracking` to `JIRA: N/A`
5. Post-create follow-up:
- share PR URLs
- call out any required labels/reviewers not applied automatically
- keep branch grouping rationale brief and explicit

## Terraform Rules

- Prefer the user-provided OCI auth path first.
- When using profile auth in `oci_api/config`, set env vars on `docker-compose run`:
- `OCI_CLI_PROFILE=<profile>`
- `OCI_CLI_CONFIG_FILE=/root/.oci/config`
- `OCI_CONFIG_FILE=/root/.oci/config`
- For `abldev1_inventory`, default profile should be `abldev1` (or `config_profile_name` in `abldev1_inventory/group_vars/all.yml`).
- For `oci_inventory` (fedscale), default profile should be `fedscale`.
- Keep user `DEFAULT` profile untouched; only use `DEFAULT` when the user explicitly asks to run with it.
- Prefer user-provided secrets file path. In this repo, users may store secrets at `oci_api/secrets.tfvars`.
- Consult `terraform/README.md` for per-environment backend and centralized secrets flow details.
- For first-time init in this repo, use backend credentials from repo secrets:
  - `terraform -chdir=terraform/envs/<env> init -backend-config=../../../oci_api/secrets.tfvars`
- If `plan` fails with backend/provider initialization or lock-file mismatch, run `init` (with backend-config above for first-time env setup) and retry `plan`.
- Do not force `terraform init` if user asks to skip it. Try `plan` first and run `init` only if Terraform explicitly requires it.
- For destroy flow:
- run `plan -destroy` first
- verify plan is scoped to requested resources
- run `destroy` only after user confirmation
- verify state after destroy (for example `terraform state list`)

## Ansible Rules

- Prefer scoped runs (`-l <host-or-group>`) for host-level changes.
- Use `-t` only when user asks for tag-limited execution.
- If a scoped/tag run skips expected host bootstrap pieces, rerun scoped playbook without restrictive tags.
- Preserve interactive flags when needed (`--ask-vault-pass`).
- For `abldev1_inventory` and `oci_inventory`, block execution until OCI auth preflight passes.
- For quick connectivity/debug checks, run ad-hoc module tests with the inventory target:
- Treat `<inventory>` as the full resolved `-i ...` list for the selected env/family, not a literal token.
- Example (`abldev1_inventory`, env `ablfeda`): `-i abldev1_inventory/ablfeda.yml -i abldev1_inventory/ablfeda.oci.yml -i abldev1_inventory/abldev1_groups.yml`
- Example (`oci_inventory`, env `oci006`): `-i oci_inventory/oci006.yml -i oci_inventory/oci006.oci.yml -i oci_inventory/oci_groups.yml`
- Linux-only target set: `ansible <host-or-group> <inventory> -m ping`
- Windows-only target set: `ansible <host-or-group> <inventory> -m win_ping`
- Do not combine Linux and Windows hosts in the same quick test command; split into separate runs.

## Troubleshooting Notes

- If the repo is missing locally, or `gh` and `git` are unavailable, switch first to repo access setup instead of improvising around missing tooling.
- If enterprise GitHub access fails, verify VPN or DH2/OCI network reachability before treating the repo as unavailable.
- SSH key content in secrets/vars may require a trailing newline. If auth fails unexpectedly after key updates, verify newline at EOF.
- If profile/auth errors occur, compare `config_profile` in `<env>.oci.yml` with profile sections in `oci_api/config` and verify `key_file` paths resolve inside container as `/root/.oci/...`.
- If user is on Windows and dockerized TACO is unavailable there, run TACO by SSHing into the user-owned Linux runner instead of copying creds to a shared host.
- If Docker setup/permissions are the blocker, switch to `docker-runner-setup` first, then return to this skill for TACO execution.
- If branch is behind or has diverged from origin, sync branch first to avoid running automation from stale code.
- If `gh` CLI is unavailable for PR creation, push branch and provide compare URL/manual PR instructions.
- If `gh pr list/create` fails with `unknown flag: --hostname`, switch to `-R <host/org/repo>`.
- If `gh` reports connectivity issues to GHE, retry once and then provide manual PR URLs.
- If the user really needs shared Abilities Center context instead of TACO execution details, switch to `abilities-center-guide` instead of stretching this skill.
- If the user needs generic repo contribution or release guidance beyond TACO-specific conventions, route to `repo-workflow-guide`.

## Command Selection

Use `references/command-patterns.md` for exact syntax.
Use `references/node-types.md` to interpret node-type language (for example "injector", "citrix", "generic") and decide when to ask clarifying questions.
Use `references/node-types.md` `## Common Roles` as the quick role-intent map before selecting playbooks.

Selection map:
- `lab_inventory` -> run `lab_inventory/playbook.yml` with lab inventories.
- `oci_inventory` -> run `oci_inventory/playbook.yml` with OCI inventories.
- `abldev1_inventory` -> run `abldev1_inventory/playbook.yml` with abldev1 inventories.
- `terraform` -> allow only for `abldev1` flows with scoped plan/apply/destroy.

Inventory selection rule:
- Treat inventory placeholders in command templates as fully resolved inventory arguments (`-i ... -i ...`) for the selected family/env, not a single literal token.

## Response Style

- Explain command choice in one sentence.
- Show exact command before execution.
- Ask one concise unblocker question when required input is missing.
- After execution, summarize outcomes and next safest command.
- When user gives ambiguous node type names (especially `injector`, `eggplant`, `citrix`, or `generic`), ask one targeted clarification before running.
