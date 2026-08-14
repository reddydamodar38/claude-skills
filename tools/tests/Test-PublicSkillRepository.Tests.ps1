[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$validator = Join-Path (Split-Path -Parent $PSScriptRoot) 'Test-PublicSkillRepository.ps1'
if (-not (Test-Path -LiteralPath $validator -PathType Leaf)) {
  throw "Missing publication validator: $validator"
}

$fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ('public-skill-validator-' + [guid]::NewGuid().ToString('N'))
$cleanRoot = Join-Path $fixtureRoot 'clean'
$dirtyRoot = Join-Path $fixtureRoot 'dirty'

function New-TestSkill {
  param(
    [string]$RepositoryRoot,
    [string]$ScriptContent
  )
  $skillRoot = Join-Path $RepositoryRoot 'codex-skills\example-skill'
  New-Item -ItemType Directory -Path (Join-Path $skillRoot 'scripts') -Force | Out-Null
  Set-Content -LiteralPath (Join-Path $skillRoot 'SKILL.md') -Encoding UTF8 -Value @'
---
name: example-skill
description: Use when validating a publication fixture.
---

# Example Skill
'@
  Set-Content -LiteralPath (Join-Path $skillRoot 'scripts\example.ps1') -Encoding UTF8 -Value $ScriptContent
}

try {
  New-TestSkill -RepositoryRoot $cleanRoot -ScriptContent 'Password = $env:EXAMPLE_PASSWORD'
  New-TestSkill -RepositoryRoot $dirtyRoot -ScriptContent "Password = 'embedded-secret'"

  & $validator -Root $cleanRoot | Out-Null

  $dirtyRejected = $false
  try {
    & $validator -Root $dirtyRoot | Out-Null
  }
  catch {
    $dirtyRejected = $_.Exception.Message -match 'literal credential assignment'
  }

  if (-not $dirtyRejected) {
    throw 'Expected a repository containing an embedded password to be rejected.'
  }

  Write-Output 'PASS: clean repositories pass and embedded credentials are rejected.'
}
finally {
  if (Test-Path -LiteralPath $fixtureRoot) {
    Remove-Item -LiteralPath $fixtureRoot -Recurse -Force
  }
}
