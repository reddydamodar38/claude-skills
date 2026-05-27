param(
  [Parameter(Mandatory=$true)][string]$HostName,
  [Parameter(Mandatory=$true)][string]$UserName,
  [Parameter(Mandatory=$true)][string]$RemoteDir,
  [string]$Pattern = "ERROR|WARN|FATAL|Exception",
  [string]$KeyPath,
  [string]$Password
)

$ErrorActionPreference = "Stop"

if (-not $KeyPath -and -not $Password) {
  throw "Provide either -KeyPath or -Password for SSH authentication."
}

if ($KeyPath -and $Password) {
  throw "Use only one auth mode: -KeyPath or -Password."
}

function Escape-BashSingleQuoted([string]$Value) {
  $bashQuoteBreak = "'" + '"' + "'" + '"' + "'"
  return $Value.Replace("'", $bashQuoteBreak)
}

$escapedRemoteDir = Escape-BashSingleQuoted $RemoteDir
$escapedPattern = Escape-BashSingleQuoted $Pattern

# Build a single-line bash command to avoid Windows newline/continuation parsing issues over SSH.
$remoteCmd = @(
  "set -e",
  "if [ ! -d '$escapedRemoteDir' ]; then echo 'Remote directory not found: $escapedRemoteDir' >&2; exit 2; fi",
  "echo '=== Recent log files ==='",
  "find '$escapedRemoteDir' -type f \( -name '*.log' -o -name '*.out' \) -printf '%TY-%Tm-%Td %TH:%TM %p\n' | sort -r | head -n 20",
  "echo",
  "echo '=== Matching lines ($escapedPattern) ==='",
  "find '$escapedRemoteDir' -type f \( -name '*.log' -o -name '*.out' \) -print0 | xargs -0 grep -nE '$escapedPattern' 2>/dev/null | tail -n 300"
) -join "; "

if ($KeyPath) {
  $sshArgs = @("-i", $KeyPath, "$UserName@$HostName", $remoteCmd)
  & ssh @sshArgs
} else {
  if (-not (Get-Module -ListAvailable -Name Posh-SSH)) {
    throw "Posh-SSH module is required for password mode on Windows. Install with: Install-Module Posh-SSH -Scope CurrentUser"
  }

  Import-Module Posh-SSH -ErrorAction Stop

  $securePassword = ConvertTo-SecureString $Password -AsPlainText -Force
  $credential = New-Object System.Management.Automation.PSCredential($UserName, $securePassword)

  $session = New-SSHSession -ComputerName $HostName -Credential $credential -AcceptKey -ErrorAction Stop
  try {
    $result = Invoke-SSHCommand -SessionId $session.SessionId -Command $remoteCmd -TimeOut 120000
    if ($result.Output) {
      $result.Output | ForEach-Object { $_ }
    }
    if ($result.Error) {
      $result.Error | ForEach-Object { Write-Error $_ }
    }
    if ($result.ExitStatus -ne 0) {
      throw "Remote command failed with exit status $($result.ExitStatus)."
    }
  } finally {
    Remove-SSHSession -SessionId $session.SessionId | Out-Null
  }
}
