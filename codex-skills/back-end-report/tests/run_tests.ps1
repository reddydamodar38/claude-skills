param([string]$Group = 'all')
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$patterns = if ($Group -eq 'all') { @('*.Tests.ps1') } else { @("*$Group*.Tests.ps1") }
$tests = @($patterns | ForEach-Object { Get-ChildItem -LiteralPath $root -Filter $_ -File } | Sort-Object FullName -Unique)
if (-not $tests.Count) { throw "No tests found for group '$Group'." }
$failed = 0
foreach ($test in $tests) {
    Write-Output "TEST: $($test.Name)"
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $test.FullName
    if ($LASTEXITCODE -ne 0) { $failed++ }
}
if ($failed) { throw "$failed test file(s) failed." }
Write-Output "PASS: $($tests.Count) test file(s)"

