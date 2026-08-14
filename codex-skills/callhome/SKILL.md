---
name: callhome
description: Use when recovering Cerner ESM Sentinel callhome folders or restarting the Cerner System Management Agent on Windows CTX nodes, especially when targets come from TORQ/Jenkins and credentials are managed by node-orchestration.
---

# Callhome

Use this skill to check, rotate, and recover `callhome` folders for Cerner ESM Sentinel on Windows CTX nodes.

The full recovery workflow deletes any existing `callhome_bkp`, moves `callhome` to `callhome_bkp`, starts `SentinelEsm`, and verifies that a new `callhome` folder is created. For check-only or rotate-only requests, do not start or stop services unless explicitly requested or needed to release a folder lock.

## Inputs To Edit Each Run

- `domain`: named domain to run, default `ablscale3`
- `jenkinsBaseUrl`: optional TORQ/Jenkins base URL such as `http://dh2torqvip1.dh2.cerner.com/ablscale3/`
- `domainNodeMap`: fallback map of domain names to CTX hostnames
- `domainUser`: domain username, format `domain\user`
- `password`: `<secure prompt>` only unless explicitly provided by the user
- `sentinelPath`: default `C:\Program Files\CernerESM\sentinel`
- `serviceName`: default `SentinelEsm`
- `mode`: `check-only`, `rotate-only`, `rotate-and-start`, or `start-agent-only`

## Mode Selection

- `check-only`: identify CTX nodes, report Jenkins online/offline state, `SentinelEsm` status, and whether `callhome` / `callhome_bkp` exist. Do not change files or services.
- `rotate-only`: delete only the exact `callhome_bkp` child under the sentinel path, then move `callhome` to `callhome_bkp`. Leave `SentinelEsm` in its current state unless the move is blocked by a lock.
- `rotate-and-start`: rotate folders, then start or restart `SentinelEsm` and verify both the backup `callhome_bkp` and newly-created `callhome` exist.
- `start-agent-only`: start or restart `SentinelEsm` and verify that `callhome` exists. Use this after a previous rotate-only pass.

When the user says "check", use `check-only`. When the user says "delete callhome_bkp and move callhome", use `rotate-only`. When the user says "start/restart Cerner System Management Agent", use `start-agent-only` for the previously selected CTX nodes unless they ask for another domain.

## Domain Selection

Use the domain name the user mentions. For example, if the user says `ablscale3`, set `$domain = 'ablscale3` and run only that domain's CTX nodes.

If the user provides a TORQ/Jenkins domain URL, prefer discovering CTX nodes from Jenkins first:

```powershell
$base = 'http://dh2torqvip1.dh2.cerner.com/ablscale3'
$data = (Invoke-WebRequest -Uri "$base/computer/api/json?tree=computer[displayName,offline,temporarilyOffline]" -UseBasicParsing).Content | ConvertFrom-Json
$ctxNodes = @($data.computer | Where-Object { $_.displayName -match 'CTX' } | Select-Object -ExpandProperty displayName | Sort-Object -Unique)
```

Use the static `domainNodeMap` only when Jenkins is unavailable or the user asks for a known subset.
## Fast TORQ and Node-Orchestration Path

For a restart request, use this path before the admin-share pattern. Use the existing encrypted node-orchestration vault; never print, copy, or hardcode credential values.

1. Delegate a read-only sub-agent to query the TORQ computer API and return the deduplicated online CTX names. The sub-agent must not restart services, modify inventories, or access secret values.
2. Query `http://dh2torqvip1.dh2.cerner.com/<domain>/computer/api/json?tree=computer[displayName,offline,temporarilyOffline]`. Keep only `CTX` nodes that are neither `offline` nor `temporarilyOffline`.
3. Connect to the runner. If `ssh codex-runner` does not resolve, connect to the same approved host as `ssh root@dh2vpc067.dh2.cerner.com`; verify `hostname`, `id -un`, and `pwd`.
4. Use the existing `/root/node-orchestration` checkout. Preserve its dirty worktree; do not fetch, pull, or edit tracked inventories for this operational task.
5. Use `-i lab_inventory/<domain> -i lab_inventory/lab_groups.yml` plus `--vault-password-file /home/taco/.codex_tmp/vault-pass.txt`. `lab_groups.yml` is required for WinRM/CredSSP.
6. If TORQ nodes are absent from the static inventory, place a temporary non-secret inventory in `/root/node-orchestration/.codex_tmp/` that adds the exact FQDNs to `citrix-vda`. The file must be inside the checkout so Docker mounts it. Do not target inventory-only CTX nodes absent from TORQ.
7. Run `docker compose run --rm taco ansible` with `ansible.windows.win_ping` against the exact TORQ hostname list. Restart only when every requested node returns `pong`; report unreachable nodes instead of omitting them.
8. Run `ansible.windows.win_service -a 'name=SentinelEsm state=restarted'` against that exact list, then separately query `ansible.windows.win_service -a 'name=SentinelEsm'`. Success requires `exists=true` and `state=running` for every node.

```bash
cd /root/node-orchestration
docker compose run --rm taco ansible '<hosts>' \
  -i lab_inventory/<domain> -i lab_inventory/lab_groups.yml \
  -i .codex_tmp/callhome-torq-ctx.yml \
  --vault-password-file /home/taco/.codex_tmp/vault-pass.txt \
  -m ansible.windows.win_service -a 'name=SentinelEsm state=restarted'
```

Known `ablscale3` CTX nodes include:

```powershell
$domainNodeMap = @{
  ablscale3 = @(
    'DH2SCALE319CTX7',
    'DH2SCALE319CTX8',
    'DH2VABLSCL3CTX0',
    'DH2VABLSCL3CTX5',
    'DH2VABLSCL3CTX6',
    'DH2VABLSCL3CTX7',
    'DH2VABLSCL3CTX9',
    'DH2VLNTEC19CTX3',
    'DH2VLNTEC19CTX4'
  )
}
```

## Behavior

1. Select CTX nodes from TORQ/Jenkins for the requested domain. For service restarts, use the Fast TORQ and Node-Orchestration Path.
2. For `check-only`, query `SentinelEsm` plus `callhome` and `callhome_bkp`; make no changes.
3. For `rotate-only`, delete only `callhome_bkp` under the sentinel path, then move `callhome` to `callhome_bkp`; do not start `SentinelEsm` afterward.
4. For `rotate-and-start`, perform the folder rotation, then start or restart `SentinelEsm`.
5. For `start-agent-only`, start or restart `SentinelEsm` without moving folders.
6. Verify service status and folder presence per node.
7. Report per-node results.

## Admin-Share Pattern

Use this pattern when PowerShell Remoting is unavailable but admin shares work. It matches the tested workflow used for `ablscale3` CTX nodes.

```powershell
$nodes = @('DH2SCALE319CTX7','DH2SCALE319CTX8')
$serviceName = 'SentinelEsm'
$sentinelRel = 'Program Files\CernerESM\sentinel'
$mode = 'rotate-only' # check-only, rotate-only, rotate-and-start, start-agent-only

foreach ($node in $nodes) {
  $base = "\\$node\C$\$sentinelRel"
  $callhome = Join-Path $base 'callhome'
  $backup = Join-Path $base 'callhome_bkp'

  $svcText = (& sc.exe "\\$node" query $serviceName 2>&1) -join ' '
  $svcStatus = if ($svcText -match 'STATE\s*:\s*\d+\s+(\w+)') { $matches[1] } elseif ($svcText -match 'FAILED 1060') { 'NotFound' } else { 'Unknown' }

  if ($mode -eq 'check-only') {
    [pscustomobject]@{ Node=$node; SentinelEsm=$svcStatus; Callhome=(Test-Path -LiteralPath $callhome); CallhomeBkp=(Test-Path -LiteralPath $backup) }
    continue
  }

  if ($mode -in @('rotate-only','rotate-and-start')) {
    $resolvedBase = (Resolve-Path -LiteralPath $base).Path

    if (Test-Path -LiteralPath $backup) {
      $resolvedBackup = (Resolve-Path -LiteralPath $backup).Path
      if (-not $resolvedBackup.StartsWith($resolvedBase, [System.StringComparison]::OrdinalIgnoreCase)) { throw "Backup path outside sentinel path: $resolvedBackup" }
      Remove-Item -LiteralPath $resolvedBackup -Recurse -Force -ErrorAction Stop
    }

    if (Test-Path -LiteralPath $callhome) {
      $resolvedCallhome = (Resolve-Path -LiteralPath $callhome).Path
      if (-not $resolvedCallhome.StartsWith($resolvedBase, [System.StringComparison]::OrdinalIgnoreCase)) { throw "Callhome path outside sentinel path: $resolvedCallhome" }
      Move-Item -LiteralPath $resolvedCallhome -Destination $backup -Force -ErrorAction Stop
    }
  }

  if ($mode -in @('rotate-and-start','start-agent-only')) {
    if ($svcStatus -eq 'RUNNING') {
      sc.exe "\\$node" stop $serviceName | Out-Null
      Start-Sleep -Seconds 5
    }
    sc.exe "\\$node" start $serviceName | Out-Null
    Start-Sleep -Seconds 10
  }
}
```

## Result Guidance

- `check-only`: report all CTX nodes, Jenkins online/offline state when available, `SentinelEsm`, `callhome`, and `callhome_bkp`.
- `rotate-only`: success means `callhome=False`, `callhome_bkp=True`, and `SentinelEsm` unchanged or stopped.
- `rotate-and-start`: success means `SentinelEsm=RUNNING`, `callhome=True`, and `callhome_bkp=True`.
- `start-agent-only`: success means `SentinelEsm=RUNNING` and `callhome=True`.
- `SentinelPathExists=False`: host does not have the expected Cerner ESM path.
- `ServiceAfter != RUNNING` when start was requested: check service logs or retry service start manually.

## Safety Notes

- Do not hardcode passwords in the skill.
- Use the node-orchestration vault only through Ansible; never display its contents or pass the password as a command argument.
- Include `lab_inventory/lab_groups.yml`; otherwise CTX hosts can default to SSH instead of WinRM.
- Keep temporary TORQ inventories in `.codex_tmp` within the node-orchestration checkout; do not modify tracked inventories.
- Only delete the exact child folder `callhome_bkp` under `C:\Program Files\CernerESM\sentinel`.
- Resolve and validate paths before deleting or moving.
- Do not start `SentinelEsm` after `rotate-only` unless the user separately asks to start or restart the agent.
- Confirm the node list before running on a new domain.
