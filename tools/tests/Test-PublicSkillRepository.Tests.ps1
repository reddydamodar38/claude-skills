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
$dirtyMarkdownRoot = Join-Path $fixtureRoot 'dirty-markdown'
$workspaceArtifactRoot = Join-Path $fixtureRoot 'workspace-artifact'
$looseArtifactCases = @(
  @{ Name = 'skill-backup'; RelativePath = 'SKILL.md.pre-refresh-20260701' },
  @{ Name = 'skill-backup-alias'; RelativePath = 'SKILL.md.backup-20260814' },
  @{ Name = 'generated-parameters'; RelativePath = 'param_values_generated.csv' },
  @{ Name = 'generated-json'; RelativePath = 'parameters_generated.json' },
  @{ Name = 'generated-yaml'; RelativePath = 'parameters_generated.yaml' },
  @{ Name = 'empty-generated-prefix'; RelativePath = '_generated.csv' },
  @{ Name = 'restart-helper'; RelativePath = '.restart_batch.py' },
  @{ Name = 'empty-restart-name'; RelativePath = '.restart_.py' },
  @{ Name = 'generated-delta-report'; RelativePath = 'report_run_deltas.txt' },
  @{ Name = 'empty-report-name'; RelativePath = 'report_deltas.txt' }
)

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
  New-TestSkill -RepositoryRoot $dirtyMarkdownRoot -ScriptContent 'Password = $env:EXAMPLE_PASSWORD'
  New-TestSkill -RepositoryRoot $workspaceArtifactRoot -ScriptContent 'Password = $env:EXAMPLE_PASSWORD'
  New-Item -ItemType Directory -Path (Join-Path $workspaceArtifactRoot 'codex-skills\example-skill\.codex-gatling-batch-work') -Force | Out-Null
  Add-Content -LiteralPath (Join-Path $dirtyMarkdownRoot 'codex-skills\example-skill\SKILL.md') -Encoding UTF8 -Value '- `Password`: `embedded-markdown-secret`'
  Set-Content -LiteralPath (Join-Path $cleanRoot 'codex-skills\example-skill\scripts\example.py') -Encoding UTF8 -Value @'
def submit_login(username: str, password: str) -> None:
    pass
'@

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

  $dirtyMarkdownRejected = $false
  try {
    & $validator -Root $dirtyMarkdownRoot | Out-Null
  }
  catch {
    $dirtyMarkdownRejected = $_.Exception.Message -match 'literal credential assignment'
  }

  if (-not $dirtyMarkdownRejected) {
    throw 'Expected a Markdown-formatted embedded password to be rejected.'
  }

  $workspaceArtifactRejected = $false
  try {
    & $validator -Root $workspaceArtifactRoot | Out-Null
  }
  catch {
    $workspaceArtifactRejected = $_.Exception.Message -match 'forbidden directory'
  }

  if (-not $workspaceArtifactRejected) {
    throw 'Expected a generated Codex work directory to be rejected.'
  }

  foreach ($case in $looseArtifactCases) {
    $caseRoot = Join-Path $fixtureRoot $case.Name
    New-TestSkill -RepositoryRoot $caseRoot -ScriptContent 'Password = $env:EXAMPLE_PASSWORD'
    Set-Content -LiteralPath (Join-Path $caseRoot "codex-skills\example-skill\$($case.RelativePath)") -Encoding UTF8 -Value 'generated artifact'

    $artifactRejected = $false
    try {
      & $validator -Root $caseRoot | Out-Null
    }
    catch {
      $artifactRejected = $_.Exception.Message -match 'generated or backup artifact'
    }

    if (-not $artifactRejected) {
      throw "Expected loose generated/backup artifact to be rejected: $($case.RelativePath)"
    }
  }

  Write-Output 'PASS: clean repositories pass and embedded credentials/generated artifacts are rejected.'
}
finally {
  if (Test-Path -LiteralPath $fixtureRoot) {
    Remove-Item -LiteralPath $fixtureRoot -Recurse -Force
  }
}
