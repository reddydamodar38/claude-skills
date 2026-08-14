[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

function Assert-FileContains {
  param(
    [Parameter(Mandatory = $true)][string]$RelativePath,
    [Parameter(Mandatory = $true)][string[]]$Patterns
  )

  $path = Join-Path $repositoryRoot $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    throw "Missing expected file: $path"
  }

  $content = Get-Content -LiteralPath $path -Raw
  foreach ($pattern in $Patterns) {
    if ($content -notmatch [regex]::Escape($pattern)) {
      throw "Expected $RelativePath to reference $pattern"
    }
  }
}

Assert-FileContains -RelativePath 'codex-skills\gatling-converter\scripts\run_gatling_converter.ps1' -Patterns @(
  'GATLING_CONFIG_PASSWORD'
)

Assert-FileContains -RelativePath 'codex-skills\gatling-scenario-data-creator\scripts\run_gatling_scenario_data_creator.ps1' -Patterns @(
  'FPABL_DB_PASSWORD',
  'ABLFHIR_DB_PASSWORD',
  'FPABL_ALT_DB_PASSWORD',
  'FPABL2_DB_PASSWORD'
)

Assert-FileContains -RelativePath 'codex-skills\sqlplus\scripts\run_oracle_query.ps1' -Patterns @(
  'FPABL_DB_PASSWORD',
  'ABLFHIR_DB_PASSWORD',
  'FPSG_DB_PASSWORD',
  'ORACLE_DB_PASSWORD'
)

Assert-FileContains -RelativePath 'codex-skills\gatling-scenario-data-creator\SKILL.md' -Patterns @(
  'GATLING_CONFIG_PASSWORD',
  'FPABL_DB_PASSWORD',
  'ABLFHIR_DB_PASSWORD',
  'FPABL_ALT_DB_PASSWORD',
  'FPABL2_DB_PASSWORD'
)

Assert-FileContains -RelativePath 'codex-skills\sqlplus\SKILL.md' -Patterns @(
  'FPABL_DB_PASSWORD',
  'ABLFHIR_DB_PASSWORD',
  'FPSG_DB_PASSWORD',
  'ORACLE_DB_PASSWORD'
)

$sqlplusScript = Join-Path $repositoryRoot 'codex-skills\sqlplus\scripts\run_oracle_query.ps1'
$savedPassword = [Environment]::GetEnvironmentVariable('FPABL_DB_PASSWORD', 'Process')
$savedGenericPassword = [Environment]::GetEnvironmentVariable('ORACLE_DB_PASSWORD', 'Process')
try {
  [Environment]::SetEnvironmentVariable('FPABL_DB_PASSWORD', $null, 'Process')
  [Environment]::SetEnvironmentVariable('ORACLE_DB_PASSWORD', $null, 'Process')
  $message = $null
  try {
    & $sqlplusScript -DbEnv FPABL -Query 'select 1 from dual' 2>&1 | Out-Null
  }
  catch {
    $message = $_.Exception.Message
  }
  if ($message -notmatch 'FPABL_DB_PASSWORD') {
    throw 'Expected a missing FPABL_DB_PASSWORD value to fail with a clear environment-variable message.'
  }
}
finally {
  [Environment]::SetEnvironmentVariable('FPABL_DB_PASSWORD', $savedPassword, 'Process')
  [Environment]::SetEnvironmentVariable('ORACLE_DB_PASSWORD', $savedGenericPassword, 'Process')
}

Write-Output 'PASS: published operational credentials are supplied through documented environment variables.'
