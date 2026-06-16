---
name: torq-pre-run
description: Check and optionally recover TORQ Windows SUT and CTX machines before a pipeline using domain-based node selection. Use when Codex needs to run TORQ pre-run readiness or recovery for a named domain such as ablscale3, verify reachability, disk space, temp pressure, xaauto artifacts, Recycle Bin usage, unloaded XAauto profiles, TorqJenkinsAgent status, optional agent start, slow CTX login recovery by restarting Citrix BrokerAgent, and optional CTX reboot. Reboot must happen only when the user explicitly includes -reboot.
---

# TORQ Pre-Run

Use this skill before a TORQ pipeline when Windows SUT or CTX nodes need readiness checks, `xaauto` cleanup, agent recovery, slow CTX login recovery, or a controlled CTX reboot.

Default to read-only readiness. Make changes only when the user asks to clean, delete, clear, recover, fix, start the agent, or run auto-recovery.

When the user names a domain, select nodes only from that domain's map entry. Do not require the user to list every SUT or CTX machine.

## Reboot Rule

Only reboot when the user explicitly includes the literal `-reboot` flag.

- If the user says `-reboot`, set `$reboot = $true`.
- If the user does not say `-reboot`, keep `$reboot = $false`.
- Do not infer reboot from "auto-recovery", "fix", "cleanup", "pre-run", or "TORQ".

## Modes

- `readiness`: report reachability, free disk, temp pressure, `xaauto` item count, Recycle Bin size, unloaded `XAauto` profile count, and `TorqJenkinsAgent` status.
- `cleanup`: delete matching `xaauto` temp files/folders, optionally clear Recycle Bin, optionally remove unloaded `XAauto` user profiles, then re-run readiness.
- `agent-recovery`: start `TorqJenkinsAgent` when it exists but is not running.
- `ctx-login-recovery`: when a CTX node is taking too long to login/connect, restart `BrokerAgent` remotely without RDP, wait 20 seconds, verify the service, and inspect recent Citrix/.NET/Application Error events.
- `auto-recovery`: cleanup plus agent recovery. It does not reboot unless the user includes `-reboot`.
- `ctemp-only`: restrict cleanup to `C:\Temp` when the user explicitly asks for that path only.
- `reboot`: reboot CTX nodes only when `-reboot` is present, then wait and recheck all nodes.

## Inputs To Edit Each Run

- `domain`: named TORQ domain to run, default `ablscale3`
- `domainNodeMap`: map of domain names to their CTX and SUT hostnames
- `ctxNodes`: selected from `domainNodeMap[$domain]`, used for optional `-reboot`
- `sutNodes`: selected from `domainNodeMap[$domain]`
- `nodes`: selected domain's SUT and CTX hostnames
- `domainUser`: domain username, format `domain\user`
- `password`: secure prompt only unless explicitly requested otherwise
- `serviceName`: default `TorqJenkinsAgent`
- `brokerServiceName`: default `BrokerAgent` for CTX slow-login recovery
- `minFreeGB`: default `20`
- `targetPattern`: default `*xaauto*`
- `performCleanup`: `$false` for report-only, `$true` for cleanup plus recheck
- `startTorqAgent`: `$false` for report-only, `$true` when agent recovery is requested
- `reboot`: `$true` only when the user includes `-reboot`
- `pathMode`: `torq`, `default`, or `ctemp-only`
- `clearRecycleBin`: default `$true` when cleanup is requested
- `removeUnloadedXaautoProfiles`: default `$true` when cleanup is requested
- `bootWaitSeconds`: default `120`

## Domain Selection

Use the domain name the user mentions. For example, if the user says `ablscale3`, set `$domain = 'ablscale3'` and run only the nodes under that map entry.

Add future domains by adding a new key to `$domainNodeMap`:

```powershell
$domainNodeMap['newdomain'] = @{
  ctxNodes = @('CTX_HOST_1', 'CTX_HOST_2')
  sutNodes = @('SUT_HOST_1', 'SUT_HOST_2')
}
```

## Path Selection

- `torq`: `$env:TEMP`, `C:\Windows\Temp`, and `C:\Temp`
- `default`: `$env:TEMP` and `C:\Windows\Temp`
- `ctemp-only`: `C:\Temp` only

When a user asks for path-restricted cleanup, honor the requested scope exactly.

## Flag Mapping

- Readiness only: `$performCleanup = $false`, `$startTorqAgent = $false`, `$reboot = $false`
- Cleanup only: `$performCleanup = $true`, `$startTorqAgent = $false`, `$reboot = $false`
- Auto-recovery without reboot: `$performCleanup = $true`, `$startTorqAgent = $true`, `$reboot = $false`
- Auto-recovery with `-reboot`: `$performCleanup = $true`, `$startTorqAgent = $true`, `$reboot = $true`
- Reboot only with `-reboot`: `$performCleanup = $false`, `$startTorqAgent = $false`, `$reboot = $true`
- CTX slow-login recovery: restart `BrokerAgent` on the named CTX only; keep `$reboot = $false`

## CTX Slow-Login Recovery

Use this when the user says a CTX is taking too long to login, Citrix connect is slow, or a reference TX/RDP/Citrix connection is hanging. Do not open RDP for this recovery.

Prefer the CTX hostname because WinRM with an IP can require TrustedHosts or explicit credentials. Use the domain credential only through `Get-Credential` or an existing secure session; do not hardcode passwords.

```powershell
$ctxNode = 'DH2SCALE319CTX7'

Invoke-Command -ComputerName $ctxNode -ScriptBlock {
  Restart-Service -Name BrokerAgent -Force
  Start-Sleep -Seconds 20

  Get-Service -Name BrokerAgent |
    Select-Object Name,Status,StartType,DisplayName

  Get-WinEvent -FilterHashtable @{LogName='Application'; StartTime=(Get-Date).AddMinutes(-10)} |
    Where-Object { $_.ProviderName -match 'Citrix Desktop Service|\.NET Runtime|Application Error' } |
    Select-Object TimeCreated,ProviderName,Id,LevelDisplayName,Message
}
```

If `Invoke-Command` fails because WinRM rejects the IP path, retry with the CTX hostname. If WinRM is unavailable and the user has an approved credential context such as `runas /netonly /user:dh2\ablscale3cert powershell`, use remote service control from that shell:

```powershell
sc.exe \\DH2SCALE319CTX7 stop BrokerAgent
sc.exe \\DH2SCALE319CTX7 start BrokerAgent
sc.exe \\DH2SCALE319CTX7 query BrokerAgent
```

Success criteria:
- `BrokerAgent` is `Running`.
- Recent events include Citrix Desktop Service startup/registration, especially event `1012` registering with a delivery controller.
- Report any `.NET Runtime` or `Application Error` events found in the same 10-minute window.

## Unified PowerShell Command

```powershell
$domainUser = 'dh2\ablscale3cert'
$password = Read-Host "Password for $domainUser" -AsSecureString
$cred = New-Object System.Management.Automation.PSCredential($domainUser, $password)

$domain = 'ablscale3'

$domainNodeMap = @{
  ablscale3 = @{
    ctxNodes = @(
      'DH2SCALE319CTX7',
      'DH2SCALE319CTX8',
      'DH2VABLSCL3CTX5',
      'DH2VABLSCL3CTX6',
      'DH2VLNTEC19CTX3',
      'DH2VLNTEC19CTX4'
    )
    sutNodes = @(
      'DH2VABLSCL2SUT2',
      'DH2VABLSCL2SUT3',
      'DH2VABLSCL2SUT4',
      'DH2VABLSCL2SUT5',
      'DH2VABLSCL4SUT5',
      'DH2VABLSCL4SUT6'
    )
  }
}

if (-not $domainNodeMap.ContainsKey($domain)) {
  throw "Unknown TORQ domain '$domain'. Add it to `$domainNodeMap before running."
}

$selectedDomain = $domainNodeMap[$domain]
$ctxNodes = @($selectedDomain['ctxNodes'])
$sutNodes = @($selectedDomain['sutNodes'])
$nodes = @($ctxNodes + $sutNodes) | Select-Object -Unique

"Selected TORQ domain: $domain"
"Selected nodes: $($nodes -join ', ')"

$serviceName = 'TorqJenkinsAgent'
$minFreeGB = 20
$targetPattern = '*xaauto*'
$pathMode = 'torq' # torq, default, or ctemp-only
$clearRecycleBin = $true
$removeUnloadedXaautoProfiles = $true
$bootWaitSeconds = 120

# Edit these based on the user request.
$performCleanup = $false
$startTorqAgent = $false
$reboot = $false # Set to $true only when the user explicitly includes -reboot.

function Invoke-TorqNodePass {
  param(
    [string[]]$TargetNodes,
    [string]$PassName,
    [bool]$DoCleanup,
    [bool]$DoStartAgent
  )

  $pingResults = foreach ($n in $TargetNodes) {
    [pscustomobject]@{
      ComputerName = $n
      PingReachable = [bool](Test-Connection -ComputerName $n -Count 1 -Quiet -ErrorAction SilentlyContinue)
    }
  }

  $reachableNodes = @(
    $pingResults |
      Where-Object { $_.PingReachable } |
      Select-Object -ExpandProperty ComputerName
  )

  $remoteResults = @()
  if ($reachableNodes.Count -gt 0) {
    $remoteResults = Invoke-Command -ComputerName $reachableNodes -Credential $cred -ScriptBlock {
      param(
        [string]$serviceName,
        [int]$minFreeGB,
        [string]$targetPattern,
        [bool]$doCleanup,
        [bool]$doStartAgent,
        [string]$pathMode,
        [bool]$clearRecycleBin,
        [bool]$removeUnloadedXaautoProfiles,
        [string]$passName
      )

      $ErrorActionPreference = 'SilentlyContinue'

      function Get-CleanupPaths {
        param([string]$mode)

        if ($mode -eq 'ctemp-only') {
          return @('C:\Temp')
        }

        $paths = @($env:TEMP, 'C:\Windows\Temp')
        if ($mode -eq 'torq') {
          $paths += 'C:\Temp'
        }

        return $paths | Where-Object { $_ } | Select-Object -Unique
      }

      function Get-NodeState {
        param(
          [string[]]$paths,
          [string]$pattern,
          [string]$svcName
        )

        $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
        $freeGB = if ($disk) { [math]::Round($disk.FreeSpace / 1GB, 2) } else { $null }

        $xaautoCount = 0
        $tempBytes = 0
        foreach ($p in $paths) {
          if (Test-Path -LiteralPath $p) {
            $items = Get-ChildItem -LiteralPath $p -Recurse -Force -ErrorAction SilentlyContinue
            $xaautoCount += @($items | Where-Object { $_.Name -like $pattern -or $_.FullName -like $pattern }).Count
            $tempBytes += ($items | Where-Object { -not $_.PSIsContainer } | Measure-Object -Property Length -Sum).Sum
          }
        }

        $recycleBytes = 0
        $rbPath = 'C:\$Recycle.Bin'
        if (Test-Path -LiteralPath $rbPath) {
          $recycleBytes = (Get-ChildItem -LiteralPath $rbPath -Recurse -Force -ErrorAction SilentlyContinue |
            Where-Object { -not $_.PSIsContainer } |
            Measure-Object -Property Length -Sum).Sum
        }

        $profileCount = @(
          Get-CimInstance Win32_UserProfile |
            Where-Object { $_.LocalPath -like '*XAauto*' -and $_.Loaded -eq $false }
        ).Count

        $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue

        [pscustomobject]@{
          FreeGB = $freeGB
          TempGB = [math]::Round(($tempBytes / 1GB), 2)
          RecycleBinGB = [math]::Round(($recycleBytes / 1GB), 2)
          XaautoItemCount = $xaautoCount
          UnloadedXaautoProfileCount = $profileCount
          ServiceFound = [bool]$svc
          ServiceStatus = if ($svc) { $svc.Status.ToString() } else { 'NotFound' }
        }
      }

      $paths = Get-CleanupPaths -mode $pathMode
      $before = Get-NodeState -paths $paths -pattern $targetPattern -svcName $serviceName

      $deletedCandidates = 0
      $removedProfiles = 0
      $recycleAction = 'Skipped'

      if ($doCleanup) {
        foreach ($p in $paths) {
          if (Test-Path -LiteralPath $p) {
            $matches = Get-ChildItem -LiteralPath $p -Recurse -Force -ErrorAction SilentlyContinue |
              Where-Object { $_.Name -like $targetPattern -or $_.FullName -like $targetPattern }
            $deletedCandidates += @($matches).Count
            $matches | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
          }
        }

        if ($removeUnloadedXaautoProfiles) {
          $profiles = Get-CimInstance Win32_UserProfile |
            Where-Object { $_.LocalPath -like '*XAauto*' -and $_.Loaded -eq $false }
          $removedProfiles = @($profiles).Count
          $profiles | Remove-CimInstance -ErrorAction SilentlyContinue
        }

        if ($clearRecycleBin) {
          Clear-RecycleBin -Force -ErrorAction SilentlyContinue
          $rbPath = 'C:\$Recycle.Bin'
          if (Test-Path -LiteralPath $rbPath) {
            Get-ChildItem -LiteralPath $rbPath -Force -ErrorAction SilentlyContinue |
              Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
          }
          $recycleAction = 'Cleared'
        }
      }

      $serviceAction = 'None'
      $svcBefore = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
      $serviceBeforeStatus = if ($svcBefore) { $svcBefore.Status.ToString() } else { 'NotFound' }
      if ($doStartAgent -and $svcBefore -and $svcBefore.Status -ne 'Running') {
        Start-Service -Name $serviceName -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        $serviceAction = 'Start-Service'
      }

      $after = Get-NodeState -paths $paths -pattern $targetPattern -svcName $serviceName

      $reasons = @()
      if ($after.FreeGB -lt $minFreeGB) { $reasons += "Free space below ${minFreeGB}GB" }
      if ($after.XaautoItemCount -gt 0) { $reasons += 'xaauto temp artifacts present' }
      if ($after.ServiceStatus -ne 'Running') { $reasons += "TorqJenkinsAgent is $($after.ServiceStatus)" }

      [pscustomobject]@{
        ComputerName = $env:COMPUTERNAME
        Pass = $passName
        Mode = if ($doCleanup -and $doStartAgent) { 'AutoRecovery' } elseif ($doCleanup) { 'CleanupAndRecheck' } elseif ($doStartAgent) { 'AgentRecovery' } else { 'ReadinessOnly' }
        Readiness = if ($reasons.Count -eq 0) { 'Ready' } elseif ($after.FreeGB -lt $minFreeGB -or $after.ServiceStatus -ne 'Running') { 'ActionNeeded' } else { 'Warning' }
        Reason = if ($reasons.Count -eq 0) { 'OK' } else { $reasons -join '; ' }
        FreeGBBefore = $before.FreeGB
        FreeGBAfter = $after.FreeGB
        TempGBBefore = $before.TempGB
        TempGBAfter = $after.TempGB
        RecycleBinGBBefore = $before.RecycleBinGB
        RecycleBinGBAfter = $after.RecycleBinGB
        XaautoItemsBefore = $before.XaautoItemCount
        XaautoItemsAfter = $after.XaautoItemCount
        DeletedXaautoCandidates = $deletedCandidates
        UnloadedProfilesBefore = $before.UnloadedXaautoProfileCount
        UnloadedProfilesAfter = $after.UnloadedXaautoProfileCount
        RemovedUnloadedProfiles = $removedProfiles
        RecycleBinAction = $recycleAction
        ServiceBeforeStatus = $serviceBeforeStatus
        ServiceAction = $serviceAction
        ServiceStatus = $after.ServiceStatus
        PathMode = $pathMode
      }
    } -ArgumentList $serviceName, $minFreeGB, $targetPattern, $DoCleanup, $DoStartAgent, $pathMode, $clearRecycleBin, $removeUnloadedXaautoProfiles, $PassName
  }

  foreach ($p in $pingResults) {
    if (-not $p.PingReachable) {
      [pscustomobject]@{
        ComputerName = $p.ComputerName
        Pass = $PassName
        Mode = if ($DoCleanup -and $DoStartAgent) { 'AutoRecovery' } elseif ($DoCleanup) { 'CleanupAndRecheck' } elseif ($DoStartAgent) { 'AgentRecovery' } else { 'ReadinessOnly' }
        Readiness = 'ActionNeeded'
        Reason = 'Node not reachable'
        FreeGBAfter = $null
        XaautoItemsAfter = $null
        ServiceStatus = 'Unknown'
        PathMode = $pathMode
      }
      continue
    }

    $remoteResults |
      Where-Object { $_.PSComputerName -eq $p.ComputerName -or $_.ComputerName -eq $p.ComputerName } |
      Select-Object -First 1
  }
}

$initialReport = Invoke-TorqNodePass `
  -TargetNodes $nodes `
  -PassName 'Initial' `
  -DoCleanup $performCleanup `
  -DoStartAgent ($startTorqAgent -and -not $reboot)

$restartResults = @()
$finalReport = $initialReport

if ($reboot) {
  $restartResults = foreach ($n in $ctxNodes) {
    try {
      Restart-Computer -ComputerName $n -Credential $cred -Force -ErrorAction Stop
      [pscustomobject]@{ ComputerName = $n; RestartInitiated = $true; RestartMessage = 'Restart command sent' }
    } catch {
      [pscustomobject]@{ ComputerName = $n; RestartInitiated = $false; RestartMessage = $_.Exception.Message }
    }
  }

  Start-Sleep -Seconds $bootWaitSeconds

  $finalReport = Invoke-TorqNodePass `
    -TargetNodes $nodes `
    -PassName 'PostReboot' `
    -DoCleanup $false `
    -DoStartAgent $startTorqAgent
}

'Initial Report:'
$initialReport | Sort-Object Readiness, ComputerName | Format-Table -AutoSize

if ($reboot) {
  'CTX Reboot Results:'
  $restartResults | Sort-Object ComputerName | Format-Table -AutoSize

  'Post-Reboot Final Report:'
  $finalReport | Sort-Object Readiness, ComputerName | Format-Table -AutoSize
} else {
  'Final Report:'
  $finalReport | Sort-Object Readiness, ComputerName | Format-Table -AutoSize
}
```

## Result Guidance

- `Ready`: node is reachable, free space is above threshold, no `xaauto` temp artifacts remain, and `TorqJenkinsAgent` is running.
- `Warning`: node can probably run, but cleanup or follow-up is recommended.
- `ActionNeeded`: fix the node before launching TORQ.

## Safety Notes

- Keep `$performCleanup = $false` when the user asks only to check or report.
- Keep `$startTorqAgent = $false` when the user asks only to check or clean files.
- Keep `$reboot = $false` unless the user explicitly includes `-reboot`.
- Restarting `BrokerAgent` for slow CTX login is allowed without `-reboot`; it is a service restart, not a machine reboot.
- Use `$pathMode = 'ctemp-only'` only when the user explicitly restricts cleanup to `C:\Temp`.
- Reboot is disruptive; run it only before a planned TORQ pipeline or approved maintenance window.
- Locked files are expected and ignored.
- Recycle Bin cleanup may leave locked or protected system entries on busy hosts.
