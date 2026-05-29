---
name: windows-reboot-and-torq-agent-check
description: Reboot Windows nodes, verify they come back online, then check TorqJenkinsAgent service and start it if it is not running.
---

# Windows Reboot And Torq Agent Check

Use this skill when you need to reboot a set of Windows nodes, confirm they are reachable again, and ensure `TorqJenkinsAgent` is running.

## Inputs To Edit Each Run
- `nodes`: list of target hostnames
- `domainUser`: domain username (format: `domain\\user`)
- `password`: use secure prompt (recommended), or pass inline only if explicitly requested
- `serviceName`: default `TorqJenkinsAgent`
- `bootWaitSeconds`: default `90`

## Behavior
1. Send reboot to each node (`Restart-Computer -Force`).
2. Wait for reboot window.
3. Check node reachability with `Test-Connection`.
4. On reachable nodes, check `TorqJenkinsAgent`.
5. If service is not running, start it.
6. Return per-node status for reboot reachability and service state.

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
  'DH2VABLSCL2SUT5',
  'DH2VABLSCL2SUT4',
  'DH2VABLSCL2SUT3',
  'DH2VABLSCL2SUT2'
)

$serviceName = 'TorqJenkinsAgent'
$bootWaitSeconds = 90

$restartResults = foreach ($n in $nodes) {
  try {
    Restart-Computer -ComputerName $n -Credential $cred -Force -ErrorAction Stop
    [pscustomobject]@{ ComputerName = $n; RestartInitiated = $true; RestartMessage = 'Restart command sent' }
  } catch {
    [pscustomobject]@{ ComputerName = $n; RestartInitiated = $false; RestartMessage = $_.Exception.Message }
  }
}

Start-Sleep -Seconds $bootWaitSeconds

$reachable = foreach ($n in $nodes) {
  [pscustomobject]@{
    ComputerName = $n
    PingReachable = [bool](Test-Connection -ComputerName $n -Count 1 -Quiet -ErrorAction SilentlyContinue)
  }
}

$serviceResults = Invoke-Command -ComputerName ($reachable | Where-Object { $_.PingReachable } | Select-Object -ExpandProperty ComputerName) -Credential $cred -ScriptBlock {
  $serviceName = 'TorqJenkinsAgent'
  $svc = Get-Service -Name $serviceName -ErrorAction SilentlyContinue

  if (-not $svc) {
    [pscustomobject]@{
      ComputerName = $env:COMPUTERNAME
      ServiceFound = $false
      BeforeStatus = 'NotFound'
      ActionTaken = 'None'
      AfterStatus = 'NotFound'
    }
    return
  }

  $before = $svc.Status.ToString()
  $action = 'None'
  if ($svc.Status -ne 'Running') {
    Start-Service -Name $serviceName -ErrorAction SilentlyContinue
    $action = 'Start-Service'
    Start-Sleep -Seconds 2
  }

  $after = (Get-Service -Name $serviceName -ErrorAction SilentlyContinue).Status.ToString()
  [pscustomobject]@{
    ComputerName = $env:COMPUTERNAME
    ServiceFound = $true
    BeforeStatus = $before
    ActionTaken = $action
    AfterStatus = $after
  }
}

'Restart Results:'
$restartResults | Sort-Object ComputerName | Format-Table -AutoSize

'Reachability After Reboot:'
$reachable | Sort-Object ComputerName | Format-Table -AutoSize

'Service Results (Reachable Nodes):'
$serviceResults | Sort-Object ComputerName | Format-Table -AutoSize
```

## Preconditions
- WinRM enabled on target hosts.
- Network access from control machine to target hosts.
- Domain user has rights to reboot nodes and manage services.

## Safety Notes
- Reboot is disruptive. Use only during approved maintenance windows.
- If a node is not reachable after reboot wait, rerun only for failed nodes.
- If service fails to start, check dependent services and system event logs.
