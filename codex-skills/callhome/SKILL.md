---
name: callhome
description: Rotate Cerner ESM Sentinel callhome folders on Windows CTX nodes. Use when Codex needs to delete C:\Program Files\CernerESM\sentinel\callhome_bkp, move callhome to callhome_bkp, start or restart the Cerner System Management Agent service SentinelEsm, and verify that a new callhome directory is created. Supports domain-based CTX node selection such as ablscale3.
---

# Callhome

Use this skill to rotate `callhome` folders for Cerner ESM Sentinel on Windows CTX nodes.

The workflow deletes any existing `callhome_bkp`, moves `callhome` to `callhome_bkp`, starts `SentinelEsm`, and verifies that a new `callhome` folder is created.

## Inputs To Edit Each Run

- `domain`: named domain to run, default `ablscale3`
- `domainNodeMap`: map of domain names to CTX hostnames
- `domainUser`: domain username, format `domain\user`
- `password`: use secure prompt only unless explicitly requested otherwise
- `sentinelPath`: default `C:\Program Files\CernerESM\sentinel`
- `serviceName`: default `SentinelEsm`

## Domain Selection

Use the domain name the user mentions. For example, if the user says `ablscale3`, set `$domain = 'ablscale3'` and run only the CTX nodes under that map entry.

Add future domains by adding a new key:

```powershell
$domainNodeMap['newdomain'] = @(
  'CTX_HOST_1',
  'CTX_HOST_2'
)
```

## Behavior

1. Select CTX nodes for the requested domain.
2. Connect to each node with PowerShell Remoting.
3. If `SentinelEsm` is running, stop it so `callhome` is not locked.
4. Delete `C:\Program Files\CernerESM\sentinel\callhome_bkp` if present.
5. Move `callhome` to `callhome_bkp` if present.
6. Start `SentinelEsm`.
7. Verify service status and whether a new `callhome` folder exists.
8. Report per-node results.

## Recommended Command

```powershell
$domainUser = 'dh2\ablscale3cert'
$password = Read-Host "Password for $domainUser" -AsSecureString
$cred = New-Object System.Management.Automation.PSCredential($domainUser, $password)

$domain = 'ablscale3'

$domainNodeMap = @{
  ablscale3 = @(
    'DH2SCALE319CTX7',
    'DH2SCALE319CTX8',
    'DH2VABLSCL3CTX5',
    'DH2VABLSCL3CTX6',
    'DH2VLNTEC19CTX3',
    'DH2VLNTEC19CTX4'
  )
}

if (-not $domainNodeMap.ContainsKey($domain)) {
  throw "Unknown domain '$domain'. Add it to `$domainNodeMap before running."
}

$nodes = @($domainNodeMap[$domain]) | Select-Object -Unique
$sentinelPath = 'C:\Program Files\CernerESM\sentinel'
$serviceName = 'SentinelEsm'

"Selected domain: $domain"
"Selected CTX nodes: $($nodes -join ', ')"

$jobs = foreach ($node in $nodes) {
  Invoke-Command -ComputerName $node -Credential $cred -AsJob -ScriptBlock {
    param(
      [string]$sentinelPath,
      [string]$serviceName
    )

    $callhomePath = Join-Path $sentinelPath 'callhome'
    $backupPath = Join-Path $sentinelPath 'callhome_bkp'
    $messageParts = @()

    $sentinelExists = Test-Path -LiteralPath $sentinelPath
    if (-not $sentinelExists) {
      [pscustomobject]@{
        ComputerName = $env:COMPUTERNAME
        SentinelPathExists = $false
        DeletedBackup = $false
        MovedCallhome = $false
        ServiceBefore = 'Unknown'
        ServiceAction = 'Skipped'
        ServiceAfter = 'Unknown'
        NewCallhomeExists = $false
        CallhomeBkpExists = $false
        Message = 'Sentinel path not found'
      }
      return
    }

    $deletedBackup = $false
    $movedCallhome = $false

    $svcBefore = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    $serviceBefore = if ($svcBefore) { $svcBefore.Status.ToString() } else { 'NotFound' }
    if ($svcBefore -and $svcBefore.Status -eq 'Running') {
      try {
        Stop-Service -Name $serviceName -Force -ErrorAction Stop
        $svcBefore.WaitForStatus('Stopped', [TimeSpan]::FromSeconds(60))
        $messageParts += 'Stopped SentinelEsm before folder rotation'
      } catch {
        $messageParts += "Service stop failed: $($_.Exception.Message)"
      }
    }

    try {
      $resolvedSentinel = (Resolve-Path -LiteralPath $sentinelPath).Path

      if (Test-Path -LiteralPath $backupPath) {
        $resolvedBackup = (Resolve-Path -LiteralPath $backupPath).Path
        if (-not $resolvedBackup.StartsWith($resolvedSentinel, [System.StringComparison]::OrdinalIgnoreCase)) {
          throw "Resolved backup path is outside sentinel path: $resolvedBackup"
        }
        Remove-Item -LiteralPath $resolvedBackup -Recurse -Force -ErrorAction Stop
        $deletedBackup = $true
        $messageParts += 'Deleted existing callhome_bkp'
      } else {
        $messageParts += 'No existing callhome_bkp found'
      }

      if (Test-Path -LiteralPath $callhomePath) {
        $resolvedCallhome = (Resolve-Path -LiteralPath $callhomePath).Path
        if (-not $resolvedCallhome.StartsWith($resolvedSentinel, [System.StringComparison]::OrdinalIgnoreCase)) {
          throw "Resolved callhome path is outside sentinel path: $resolvedCallhome"
        }
        Move-Item -LiteralPath $resolvedCallhome -Destination $backupPath -Force -ErrorAction Stop
        $movedCallhome = $true
        $messageParts += 'Moved callhome to callhome_bkp'
      } else {
        $messageParts += 'No callhome folder found to move'
      }
    } catch {
      $messageParts += "Folder rotation failed: $($_.Exception.Message)"
    }

    $serviceAction = 'None'
    $svc = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    if ($svc) {
      if ($svc.Status -ne 'Running') {
        try {
          Start-Service -Name $serviceName -ErrorAction Stop
          Start-Sleep -Seconds 15
          $serviceAction = 'Start-Service'
          $messageParts += 'Started SentinelEsm'
        } catch {
          $serviceAction = 'Start-Service failed'
          $messageParts += "Service start failed: $($_.Exception.Message)"
        }
      } else {
        $serviceAction = 'AlreadyRunning'
        Start-Sleep -Seconds 5
      }
    } else {
      $serviceAction = 'ServiceNotFound'
      $messageParts += 'SentinelEsm service not found'
    }

    $svcAfter = Get-Service -Name $serviceName -ErrorAction SilentlyContinue

    [pscustomobject]@{
      ComputerName = $env:COMPUTERNAME
      SentinelPathExists = $true
      DeletedBackup = $deletedBackup
      MovedCallhome = $movedCallhome
      ServiceBefore = $serviceBefore
      ServiceAction = $serviceAction
      ServiceAfter = if ($svcAfter) { $svcAfter.Status.ToString() } else { 'NotFound' }
      NewCallhomeExists = Test-Path -LiteralPath $callhomePath
      CallhomeBkpExists = Test-Path -LiteralPath $backupPath
      Message = ($messageParts -join '; ')
    }
  } -ArgumentList $sentinelPath, $serviceName
}

$null = Wait-Job -Job $jobs -Timeout 180
$results = Receive-Job -Job $jobs -Keep

'Callhome Rotation Results:'
$results | Sort-Object ComputerName | Format-Table -AutoSize

$jobStates = $jobs | Select-Object Location, State
'Job States:'
$jobStates | Sort-Object Location | Format-Table -AutoSize

$notCompleted = @($jobs | Where-Object { $_.State -ne 'Completed' })
if ($notCompleted.Count -gt 0) {
  'Not Completed Nodes:'
  $notCompleted | Select-Object -ExpandProperty Location
  $notCompleted | Stop-Job -ErrorAction SilentlyContinue
}

Remove-Job -Job $jobs -Force -ErrorAction SilentlyContinue
```

## Fallback Guidance

If a node hangs over PowerShell Remoting, use an admin-share and `sc.exe` fallback for that single node only:

- Map `\\NODE\C$` with credentials.
- Delete `callhome_bkp` under `Program Files\CernerESM\sentinel`.
- Stop `SentinelEsm` with `sc.exe \\NODE stop SentinelEsm` if `callhome` is locked.
- Move `callhome` to `callhome_bkp`.
- Start `SentinelEsm` with `sc.exe \\NODE start SentinelEsm`.
- Verify both `callhome` and `callhome_bkp` exist.

## Result Guidance

- `NewCallhomeExists = True` and `ServiceAfter = Running`: success.
- `MovedCallhome = True` and `CallhomeBkpExists = True`: old callhome was preserved as backup.
- `SentinelPathExists = False`: host does not have the expected Cerner ESM path.
- `ServiceAfter != Running`: check service logs or retry service start manually.

## Safety Notes

- Do not hardcode passwords in the skill.
- Only delete the exact child folder `callhome_bkp` under `C:\Program Files\CernerESM\sentinel`.
- Stop `SentinelEsm` only to release the `callhome` lock, then start it again.
- Confirm the node list before running on a new domain.
