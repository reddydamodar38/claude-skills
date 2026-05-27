---
name: docker-runner-setup
description: Set up and validate Docker/Compose on a safe Linux runner for TACO (node-orchestration) and related Abilities Lab tools. Use when users need Docker installed, repaired, or verified before running dockerized automation; when users are on Windows and must SSH to a Linux runner; or when execution location must be validated to avoid shared-host credential risk.
---

# Docker Runner Setup

Prepare a safe execution host for Docker-based TACO workflows.
Prioritize host safety first, then Docker installation, then runtime validation.

## Workflow

1. Confirm execution location is allowed:
- run on user-owned Linux runner
- allow VS Code remote sessions into that Linux runner
- if current session is Windows, SSH to a user-owned Linux runner and run there
- refuse shared jump boxes/hosts for workflows that store OCI/auth material
2. Collect baseline state:
- OS and version
- current user and groups
- docker and compose availability
- docker daemon reachability (`docker ps`)
3. If Docker is missing or broken, install/fix using distro-appropriate commands from `references/install-and-verify.md`.
4. Ensure the operator can run Docker commands:
- either run with `sudo` or add user to `docker` group (then refresh session)
5. Verify TACO compatibility:
- from repo root, run `docker compose version` (or `docker-compose version`)
- verify `docker-compose.yml` exists
- run a safe smoke command such as `docker-compose run --rm taco bash -lc 'pwd && whoami'`
6. Report outcome:
- what was checked
- what was changed
- what command is safe to run next
7. Route back to `abilities-center-guide` when the question shifts from Docker host readiness into broader Abilities Center workflow, environment, repo-discovery, or test-data questions.

## Guardrails

- Do not copy credentials or `oci_api` contents onto shared hosts.
- Do not run installation commands on production/shared servers unless explicitly requested.
- Prefer least-privilege changes first; escalate only when required.
- If corporate package repos or proxies are required, stop and surface the exact missing prerequisite.

## Windows Path

- If user starts on Windows, direct execution to Linux runner over SSH.
- Keep Docker and TACO execution on that Linux runner.
- Keep OCI/auth files only on that user-owned Linux runner (or approved secure location).

## Resource Use

- Use `references/install-and-verify.md` for distro install commands, daemon checks, and post-install validation.
- If the user needs shared Abilities Center context outside Docker readiness, hand off to `abilities-center-guide`.
- If the user needs generic repo contribution, push, PR, or release guidance, hand off to `repo-workflow-guide`.
- If local `AGENTS.md` guidance exists for repo or auth defaults, treat it as machine-local context rather than rediscovering it.
- If those machine-local defaults keep helping across tasks, suggest capturing them in local `AGENTS.md`.
