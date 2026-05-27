---
name: windows-temp-xaauto-cleaner
description: Clean files/folders containing xaauto from Windows Temp locations across multiple nodes, tolerate locked files, and empty Recycle Bin. Use when users ask to run bulk Windows temp cleanup with editable host list and domain credentials.
---

# Windows Temp Xaauto Cleaner

Use this skill to clean Windows nodes remotely when temp folders contain `xaauto` artifacts.

## Inputs To Edit Each Run
- `nodes`: list of target hostnames
- `domainUser`: domain username (format: `domain\\user`)
- `password`: use secure prompt (recommended), or pass inline only if explicitly requested
- `targetPattern`: default `*xaauto*`

## Behavior
1. Connect to all listed Windows nodes via PowerShell Remoting (`Invoke-Command`).
2. Search these locations:
- `$env:TEMP`
- `C:\Windows\Temp`
3. Delete all matching files/folders recursively.
4. Ignore undeletable/locked items (`SilentlyContinue`).
5. Empty Recycle Bin on each node.

## Recommended Command (PowerShell)
```powershell
$domainUser = 'dh2\\ablscale3cert'
$password = Read-Host "Password for $domainUser" -AsSecureString
$cred = New-Object System.Management.Automation.PSCredential($domainUser, $password)

$nodes = @(
  'DH2VABLSCL3CTX5',
  'DH2VABLSCL3CTX6',
  'DH2SCALE319CTX7',
  'DH2SCALE319CTX8',
  'DH2VLNTEC19CTX4',
  'DH2VLNTEC19CTX5',
  'DH2VABLSCL2SUT5',
  'DH2VABLSCL2SUT4',
  'DH2VABLSCL2SUT3',
  'DH2VABLSCL2SUT2'
)

Invoke-Command -ComputerName $nodes -Credential $cred -ScriptBlock {
  $ErrorActionPreference = 'SilentlyContinue'
  $targetPattern = '*xaauto*'

  $paths = @($env:TEMP, 'C:\Windows\Temp')
  foreach ($p in $paths) {
    if (Test-Path $p) {
      Get-ChildItem -Path $p -Recurse -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like $targetPattern } |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    }
  }

  Clear-RecycleBin -Force -ErrorAction SilentlyContinue
}
```

## Bash Wrapper (Calls PowerShell)
```bash
#!/usr/bin/env bash
set -euo pipefail

USER_NAME='dh2\\ablscale3cert'
read -rsp "Password for ${USER_NAME}: " USER_PASS
echo

powershell -NoProfile -Command "
\$sec  = ConvertTo-SecureString '$USER_PASS' -AsPlainText -Force
\$cred = New-Object System.Management.Automation.PSCredential('$USER_NAME', \$sec)
\$nodes = @('DH2VABLSCL3CTX5','DH2VABLSCL3CTX6','DH2SCALE319CTX7','DH2SCALE319CTX8','DH2VLNTEC19CTX4','DH2VLNTEC19CTX5','DH2VABLSCL2SUT5','DH2VABLSCL2SUT4','DH2VABLSCL2SUT3','DH2VABLSCL2SUT2')
Invoke-Command -ComputerName \$nodes -Credential \$cred -ScriptBlock {
  \$ErrorActionPreference = 'SilentlyContinue'
  \$paths = @(\$env:TEMP, 'C:\Windows\Temp')
  foreach (\$p in \$paths) {
    if (Test-Path \$p) {
      Get-ChildItem -Path \$p -Recurse -Force -ErrorAction SilentlyContinue |
        Where-Object { \$_.Name -like '*xaauto*' } |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    }
  }
  Clear-RecycleBin -Force -ErrorAction SilentlyContinue
}
"
```

## Preconditions
- WinRM enabled on target hosts.
- Network access from control machine to target hosts.
- Domain user has rights to delete temp items and clear recycle bin.

## Safety Notes
- Prefer secure password prompt instead of hardcoding secrets.
- If required, run a dry run first by replacing `Remove-Item` with:
  `Select-Object FullName`.
- Locked files are expected and ignored by design.
