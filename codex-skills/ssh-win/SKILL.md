---
name: ssh-win
description: Connect to remote Windows hosts for RDP session launch and optional SSH command execution from PowerShell. Use when users ask to open Windows Remote Desktop, run remote commands on Windows, troubleshoot login/connectivity, or set up passwordless access (OpenSSH keys or saved credentials).
---

# SSH Win

Use this skill to connect to Windows hosts from PowerShell with either:
- RDP launch (`mstsc`) for interactive desktop access
- SSH (`ssh`) for command execution when OpenSSH Server is enabled on the target host

Default target in examples:
- Host: `10.191.201.183`
- Username: `dh2\\PC1970499`

## Host Aliases
- `win-secondary` = `10.191.201.183`
- `win-abldhir` = `10.191.205.19`
- `win-fpsg` = `10.37.169.204`

Use `-HostAlias` to avoid typing IPs.

## Workflow
1. Choose mode: `RDP`, `SSH`, or both.
2. Choose target: `-HostAlias` (preferred) or `-HostName`.
3. For RDP:
- Optionally cache credentials with `cmdkey`.
- Launch `mstsc /v:<host>`.
4. For SSH:
- Prefer key auth (`-i <keypath>`) for passwordless login.
- Run optional remote command.
5. Verify connection and capture useful errors for troubleshooting.

## Use Script
Run (alias):
`pwsh -NoProfile -File "C:/Users/prakash/.codex/skills/ssh-win/scripts/connect_win_remote.ps1" -HostAlias win-secondary -UserName 'dh2\\PC1970499' -Mode RDP -Password '<password>'`

Run (IP):
`pwsh -NoProfile -File "C:/Users/prakash/.codex/skills/ssh-win/scripts/connect_win_remote.ps1" -HostName 10.191.201.183 -UserName 'dh2\\PC1970499' -Mode RDP -Password '<password>'`

RDP without prompting each time (uses Windows Credential Manager):
`pwsh -NoProfile -File "C:/Users/prakash/.codex/skills/ssh-win/scripts/connect_win_remote.ps1" -HostAlias win-abldhir -UserName 'dh2\\PC1970499' -Mode RDP -Password '<password>' -PersistCredential`

SSH with key (passwordless):
`pwsh -NoProfile -File "C:/Users/prakash/.codex/skills/ssh-win/scripts/connect_win_remote.ps1" -HostAlias win-fpsg -UserName 'dh2\\PC1970499' -Mode SSH -KeyPath C:/Users/prakash/.ssh/id_ed25519 -RemoteCommand 'hostname && whoami'`

## Notes
- Do not hardcode passwords in skill files.
- This skill launches RDP sessions but does not perform interactive UI clicks inside the remote desktop.
- For true passwordless login:
  - SSH: configure OpenSSH Server on the remote Windows host and add your public key to `%USERPROFILE%\\.ssh\\authorized_keys`.
  - RDP: practical approach is cached credentials (`cmdkey`) or enterprise SSO (Kerberos/smart card), not anonymous login.
