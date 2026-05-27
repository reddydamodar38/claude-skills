param(
  [Parameter(Mandatory=$true)][string[]]$ScenarioNames,
  [string]$TargetAlias,
  [string]$HostName = "10.191.200.22",
  [string]$UserName = "root",
  [string]$Password = $env:GATLING_SSH_PASSWORD,
  [string]$KeyPath,
  [string]$LocalScriptRoot = "C:/Users/prakash/Desktop/project/NBS/gatling/script",
  [string]$LocalReportsDir = "C:/Users/prakash/Desktop/project/NBS/gatling/reports",
  [string]$CombinedOutputFileName = "Gatling-Combined-Summary.html"
)

$ErrorActionPreference = "Stop"

$runnerPath = Join-Path $PSScriptRoot "run_gatling_remote.ps1"
$summaryPath = Join-Path $PSScriptRoot "build_gatling_combined_summary.ps1"

if (-not (Test-Path $runnerPath)) { throw "Missing runner script: $runnerPath" }
if (-not (Test-Path $summaryPath)) { throw "Missing summary script: $summaryPath" }

New-Item -ItemType Directory -Path $LocalReportsDir -Force | Out-Null

$results = New-Object System.Collections.Generic.List[object]
foreach ($scenario in $ScenarioNames) {
  Write-Host "=== Running scenario: $scenario ==="
  try {
    $params = @{
      ScenarioName = $scenario
      HostName = $HostName
      UserName = $UserName
      LocalScriptRoot = $LocalScriptRoot
      LocalReportsDir = $LocalReportsDir
    }

    if (-not [string]::IsNullOrWhiteSpace($TargetAlias)) { $params.TargetAlias = $TargetAlias }
    if (-not [string]::IsNullOrWhiteSpace($KeyPath)) { $params.KeyPath = $KeyPath }
    elseif (-not [string]::IsNullOrWhiteSpace($Password)) { $params.Password = $Password }

    & $runnerPath @params
    $results.Add([PSCustomObject]@{ Scenario = $scenario; Status = "Completed" })
  }
  catch {
    Write-Warning "Scenario failed: $scenario - $($_.Exception.Message)"
    $results.Add([PSCustomObject]@{ Scenario = $scenario; Status = "Failed to run" })
  }
}

Write-Host "=== Building combined summary report ==="
& $summaryPath -ScenarioNames $ScenarioNames -LocalReportsDir $LocalReportsDir -OutputFileName $CombinedOutputFileName

$statusTable = $results | Format-Table -AutoSize | Out-String
Write-Host "Batch run status:`n$statusTable"

