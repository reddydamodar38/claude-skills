param(
  [string]$HostName = "10.191.201.183",
  [string]$HostAlias,
  [string]$UserName = "dh2\PC1970499",
  [ValidateSet("RDP", "SSH", "BOTH")]
  [string]$Mode = "RDP",
  [string]$Password,
  [switch]$PersistCredential,
  [string]$KeyPath,
  [string]$RemoteCommand
)

$ErrorActionPreference = "Stop"

$HostAliases = @{
  "win-secondary" = "10.191.201.183"
  "win-abldhir" = "10.191.205.19"
  "win-fpsg" = "10.37.169.204"
}

function Assert-CommandAvailable {
  param([string]$Name)
  if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
    throw "Required command not found in PATH: $Name"
  }
}

function Resolve-HostTarget {
  if (-not [string]::IsNullOrWhiteSpace($HostAlias)) {
    $aliasKey = $HostAlias.Trim().ToLowerInvariant()
    if (-not $HostAliases.ContainsKey($aliasKey)) {
      $supported = ($HostAliases.Keys | Sort-Object) -join ", "
      throw "Unknown HostAlias '$HostAlias'. Supported aliases: $supported"
    }
    $script:HostName = $HostAliases[$aliasKey]
    Write-Host "Resolved alias '$HostAlias' to '$HostName'."
  }
}

function Start-Rdp {
  if (-not [string]::IsNullOrWhiteSpace($Password)) {
    Write-Host "Storing credential for TERMSRV/$HostName via cmdkey..."
    cmdkey /generic:"TERMSRV/$HostName" /user:"$UserName" /pass:"$Password" | Out-Host
    if ($LASTEXITCODE -ne 0) {
      throw "cmdkey failed with exit code $LASTEXITCODE"
    }
  } elseif ($PersistCredential) {
    throw "-PersistCredential requires -Password on first run."
  }

  Write-Host "Launching Remote Desktop to $HostName ..."
  Start-Process "mstsc.exe" -ArgumentList "/v:$HostName"
}

function Start-Ssh {
  Assert-CommandAvailable -Name "ssh"

  $sshArgs = @()
  if (-not [string]::IsNullOrWhiteSpace($KeyPath)) {
    $sshArgs += @("-i", $KeyPath)
  }

  $sshArgs += "$UserName@$HostName"

  if (-not [string]::IsNullOrWhiteSpace($RemoteCommand)) {
    $sshArgs += $RemoteCommand
  }

  Write-Host "Starting SSH connection to $UserName@$HostName ..."
  & ssh @sshArgs | Out-Host
  if ($LASTEXITCODE -ne 0) {
    throw "ssh failed with exit code $LASTEXITCODE"
  }
}

Resolve-HostTarget

switch ($Mode) {
  "RDP" {
    Start-Rdp
  }
  "SSH" {
    Start-Ssh
  }
  "BOTH" {
    Start-Rdp
    Start-Ssh
  }
}
