---
name: desktop
description: Use when connecting to, running commands on, or troubleshooting the desktop Linux runner dh2vpc067 (codex-runner), including builds, tests, scripts, Docker, and repository work that do not require the local Windows session.
---

# Desktop Runner

Run eligible Linux work on `dh2vpc067.dh2.cerner.com` through the configured `codex-runner` SSH alias.

## Workflow

1. At the start of remote work, run:

   ```powershell
   ssh codex-runner "hostname; id -un; pwd"
   ```

   Expect `dh2vpc067`, `root`, and `/root`.

2. Create a task-specific directory below `/root/codex-workspace`; do not perform destructive actions outside it unless the user explicitly names the target.

3. Run each remote command with one SSH invocation, for example:

   ```powershell
   ssh codex-runner "cd /root/codex-workspace/my-task && <command>"
   ```

4. Use the local Windows session only for Codex UI work, mapped/UNC paths, Windows-only applications, or files not available on the runner.

## Connection rules

- Use `ssh codex-runner`; its SSH configuration supplies the host, `root` user, and `id_ed25519` identity.
- Never put passwords or private-key contents in commands, logs, or skill files.
- If the connection fails, report the error. Do not silently switch to a different host.
