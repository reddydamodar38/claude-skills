---
name: ssh
description: Connect to remote Linux/Unix hosts over SSH, inspect log files in a specified remote directory, and summarize errors, warnings, and suspicious patterns. Use when users ask to investigate logs on remote servers.
---

# SSH Log Analyzer

## Inputs Required
- host (IP/DNS)
- username
- auth mode (ssh key path or password)
- remote log directory (example: /var/log/myapp)
- optional grep pattern (example: ERROR|WARN|FATAL)

## Workflow
1. Validate SSH connectivity.
2. Find recent log files in the target directory.
3. Extract matching lines for important patterns.
4. Return:
   - file list scanned
   - top repeated errors
   - timeline of latest critical lines
   - next debugging steps

## Use Script
Run:
`pwsh ./scripts/analyze_remote_logs.ps1 -HostName <host> -UserName <user> -RemoteDir <dir> -Pattern "ERROR|WARN|FATAL"`

For SSH key auth:
`-KeyPath ~/.ssh/id_rsa`

For password auth:
`-Password "your-password"`
