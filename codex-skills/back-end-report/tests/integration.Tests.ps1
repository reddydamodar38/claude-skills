$ErrorActionPreference = 'Stop'
function Assert($Condition, [string]$Message) { if (-not $Condition) { throw "ASSERT: $Message" } }
$skill = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$temp = Join-Path ([IO.Path]::GetTempPath()) ('back-end-report-integration-' + [guid]::NewGuid())
try {
    $baseline = Join-Path $temp 'baseline\NODE1'
    $current = Join-Path $temp 'current\NODE1'
    $output = Join-Path $temp 'output'
    New-Item -ItemType Directory -Path $baseline,$current,$output -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $baseline 'meminfo.txt') -Value "MemAvailable: 8388608 kB`n"
    Set-Content -LiteralPath (Join-Path $current 'meminfo.txt') -Value "MemAvailable: 7340032 kB`n"
    $builder = Join-Path $skill 'scripts\build_report.ps1'
    & $builder -BaselinePath (Split-Path -Parent $baseline) -CurrentPath (Split-Path -Parent $current) -OutputDirectory $output -JsonOnly
    Assert ($LASTEXITCODE -eq 0) 'JSON-only orchestration must succeed.'
    $jsonPath = Join-Path $output 'back-end-report.json'
    Assert (Test-Path -LiteralPath $jsonPath) 'Canonical JSON must be created at the documented path.'
    $data = Get-Content -LiteralPath $jsonPath -Raw | ConvertFrom-Json
    Assert ($data.schema_version -eq '2.0') 'Builder must emit schema version 2.0.'
    Assert (@($data.report.artifact_coverage).Count -ge 2) 'Coverage must include both runs.'
    Assert ($null -ne $data.report.executive_summary) 'Executive summary data must be present before rendering.'
    Write-Output 'PASS: integration JSON-only pipeline'
} finally {
    if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force }
}
