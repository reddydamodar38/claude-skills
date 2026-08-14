[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$Root
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$rootFull = [IO.Path]::GetFullPath($Root).TrimEnd('\')
$collectionRoot = Join-Path $rootFull 'codex-skills'
$violations = [System.Collections.Generic.List[string]]::new()

if (-not (Test-Path -LiteralPath $collectionRoot -PathType Container)) {
  throw "Missing skill collection: $collectionRoot"
}

$collectionSkills = @(
  Get-ChildItem -LiteralPath $collectionRoot -Directory -Force |
    Sort-Object Name
)

foreach ($skill in $collectionSkills) {
  if (-not (Test-Path -LiteralPath (Join-Path $skill.FullName 'SKILL.md') -PathType Leaf)) {
    $violations.Add("missing SKILL.md: $($skill.FullName)")
  }
  if ($skill.Name -notmatch '^[a-z0-9]+(?:-[a-z0-9]+)*$') {
    $violations.Add("invalid skill directory name: $($skill.FullName)")
  }
}

$legacySkills = @(
  Get-ChildItem -LiteralPath $rootFull -Directory -Force |
    Where-Object {
      $_.Name -notin @('.git', 'codex-skills', 'docs', 'tools') -and
      (Test-Path -LiteralPath (Join-Path $_.FullName 'SKILL.md') -PathType Leaf)
    }
)
$scanRoots = @($collectionSkills) + @($legacySkills)
$forbiddenDirectoryNames = @('.git', '.skill-build', 'outputs', '__pycache__')
$textExtensions = @('.md', '.ps1', '.py', '.sh', '.yaml', '.yml', '.json', '.toml', '.txt', '.csv')
$privateKeyPattern = '-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----'
$tokenPattern = '(?:ghp_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,}|glpat-[A-Za-z0-9_-]{20,}|xox[baprs]-[A-Za-z0-9-]{20,}|AKIA[0-9A-Z]{16}|ASIA[0-9A-Z]{16})'
$assignmentPattern = '(?i)\b(password|passwd|secret|api[_-]?key)\b\s*[:=]\s*(?<value>[^\s#;,}]+)'
$safeAssignmentPattern = '^(?:\$|\$\{|<|\[|\{|ConvertTo-|Get-|Read-|None$|null$|example|placeholder|REPLACE_|REDACTED)'

foreach ($scanRoot in $scanRoots) {
  $nestedDirectories = @(
    Get-ChildItem -LiteralPath $scanRoot.FullName -Directory -Recurse -Force -ErrorAction Stop
  )
  foreach ($directory in $nestedDirectories) {
    if ($directory.Name -in $forbiddenDirectoryNames -or $directory.Name -like '*.backup-*') {
      $violations.Add("forbidden directory: $($directory.FullName)")
    }
  }

  $files = @(
    Get-ChildItem -LiteralPath $scanRoot.FullName -File -Recurse -Force -ErrorAction Stop
  )
  foreach ($file in $files) {
    if ($file.Length -gt 100000000) {
      $violations.Add("file exceeds 100 MB publication limit: $($file.FullName)")
    }
    if ($file.Extension -eq '.pyc' -or $file.Name -like 'report*.html') {
      $violations.Add("generated file: $($file.FullName)")
    }
    if ($file.Name -match '(?i)^(?:auth\.json|credentials?(?:\..+)?|\.env(?:\..+)?|id_rsa|id_ed25519)$' -or
        $file.Extension -match '(?i)^\.(?:pem|pfx|key)$') {
      $violations.Add("credential file: $($file.FullName)")
    }
    if ($file.Extension -notin $textExtensions) {
      continue
    }

    $lineNumber = 0
    foreach ($line in [IO.File]::ReadLines($file.FullName)) {
      $lineNumber++
      if ($line -match $privateKeyPattern) {
        $violations.Add("private key material: $($file.FullName):$lineNumber")
      }
      if ($line -match $tokenPattern) {
        $violations.Add("access token prefix: $($file.FullName):$lineNumber")
      }
      $assignment = [regex]::Match($line, $assignmentPattern)
      if ($assignment.Success) {
        $value = $assignment.Groups['value'].Value.Trim(("'`"").ToCharArray())
        if ($value -notmatch $safeAssignmentPattern) {
          $violations.Add("literal credential assignment: $($file.FullName):$lineNumber")
        }
      }
    }
  }
}

if ($violations.Count -gt 0) {
  throw ("Public skill validation failed:`n - " + ($violations -join "`n - "))
}

Write-Output "PASS: validated $($collectionSkills.Count) collection skills and $($legacySkills.Count) legacy copies."
