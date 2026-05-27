param(
  [string]$RepoPath,
  [string]$SkillsDir,
  [switch]$RefreshLinks,
  [switch]$NoPull,
  [switch]$AutostashPull,
  [int]$MaxDepth = 4
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Test-CodexRepo {
  param([string]$PathValue)
  if (-not (Test-Path -LiteralPath $PathValue -PathType Container)) { return $false }
  if (-not (Test-Path -LiteralPath (Join-Path $PathValue ".git"))) { return $false }
  if (-not (Test-Path -LiteralPath (Join-Path $PathValue "README.md"))) { return $false }
  return $true
}

function Resolve-AbsolutePath {
  param([string]$PathValue)
  return (Resolve-Path -LiteralPath $PathValue).Path
}

function New-SkillLink {
  param(
    [string]$DestinationPath,
    [string]$SourcePath
  )

  try {
    New-Item -Path $DestinationPath -ItemType Junction -Target $SourcePath | Out-Null
    return "Junction"
  } catch {
    New-Item -Path $DestinationPath -ItemType SymbolicLink -Target $SourcePath | Out-Null
    return "SymbolicLink"
  }
}

function Update-SkillLink {
  param(
    [string]$DestinationPath,
    [string]$SourcePath
  )

  Remove-Item -LiteralPath $DestinationPath -Force
  return (New-SkillLink -DestinationPath $DestinationPath -SourcePath $SourcePath)
}

function Find-CodexRepo {
  $candidates = New-Object System.Collections.Generic.List[string]

  if (Test-CodexRepo -PathValue $PWD.Path) {
    $candidates.Add((Resolve-AbsolutePath -PathValue $PWD.Path))
  }

  $gitTop = $null
  try {
    $gitTop = (& git rev-parse --show-toplevel 2>$null)
  } catch {
    $gitTop = $null
  }
  if ($gitTop -and (Test-CodexRepo -PathValue $gitTop)) {
    $candidates.Add((Resolve-AbsolutePath -PathValue $gitTop))
  }

  $common = @(
    (Join-Path $HOME "git\codex-skills"),
    (Join-Path $HOME "src\codex-skills"),
    (Join-Path $HOME "code\codex-skills")
  )
  foreach ($c in $common) {
    if (Test-CodexRepo -PathValue $c) {
      $candidates.Add((Resolve-AbsolutePath -PathValue $c))
    }
  }

  $found = Get-ChildItem -Path $HOME -Directory -Filter "codex-skills" -Recurse -Depth $MaxDepth -ErrorAction SilentlyContinue
  foreach ($item in $found) {
    if (Test-CodexRepo -PathValue $item.FullName) {
      $candidates.Add((Resolve-AbsolutePath -PathValue $item.FullName))
    }
  }

  if ($candidates.Count -eq 0) {
    throw "Could not auto-discover a codex-skills repo. Use -RepoPath."
  }

  $unique = $candidates | Sort-Object -Unique
  $latest = $unique |
    Sort-Object { (Get-Item -LiteralPath $_).LastWriteTimeUtc } -Descending |
    Select-Object -First 1
  return $latest
}

if (-not $RepoPath) {
  $RepoPath = Find-CodexRepo
}

$RepoPath = Resolve-AbsolutePath -PathValue $RepoPath
if (-not (Test-CodexRepo -PathValue $RepoPath)) {
  throw "Invalid repo path: $RepoPath"
}

if (-not $SkillsDir) {
  $codexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME ".codex" }
  $SkillsDir = Join-Path $codexHome "skills"
}

if (-not (Test-Path -LiteralPath $SkillsDir)) {
  New-Item -Path $SkillsDir -ItemType Directory -Force | Out-Null
}
$SkillsDir = Resolve-AbsolutePath -PathValue $SkillsDir

Write-Host "Repo path:  $RepoPath"
Write-Host "Skills dir: $SkillsDir"

if (-not $NoPull) {
  $dirty = (& git -C $RepoPath status --porcelain)
  if ($dirty) {
    if ($AutostashPull) {
      $stashMessage = "codex-skills-updater-autostash-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
      Write-Host "Working tree is dirty; attempting autostash pull."
      & git -C $RepoPath stash push -u -m $stashMessage
      if ($LASTEXITCODE -ne 0) { throw "git stash push failed" }
      Write-Host "Fetching latest changes..."
      & git -C $RepoPath fetch --all --prune
      if ($LASTEXITCODE -ne 0) { throw "git fetch failed" }
      Write-Host "Pulling with --ff-only..."
      & git -C $RepoPath pull --ff-only
      if ($LASTEXITCODE -ne 0) { throw "git pull --ff-only failed" }

      $stashList = (& git -C $RepoPath stash list)
      if ($LASTEXITCODE -ne 0) { throw "git stash list failed" }
      if ($stashList -match [Regex]::Escape($stashMessage)) {
        Write-Host "Re-applying stashed changes..."
        & git -C $RepoPath stash pop
        if ($LASTEXITCODE -ne 0) {
          Write-Host ""
          Write-Host "Autostash re-apply had conflicts. Your stash entry is still available."
          Write-Host "To resolve:"
          Write-Host "  1) cd '$RepoPath'"
          Write-Host "  2) git status"
          Write-Host "  3) resolve conflict markers in files, then git add <resolved-files>"
          Write-Host "  4) git commit -m 'Resolve autostash conflicts' (or keep changes uncommitted)"
          Write-Host "  5) if needed, inspect stash entries with: git stash list"
        }
      }
    } else {
      Write-Host "Working tree is dirty; skipping pull."
      Write-Host "Tip: rerun with -AutostashPull to stash local changes, pull safely, then re-apply."
    }
  } else {
    Write-Host "Fetching latest changes..."
    & git -C $RepoPath fetch --all --prune
    Write-Host "Pulling with --ff-only..."
    & git -C $RepoPath pull --ff-only
  }
}

$skillDirs = Get-ChildItem -Path $RepoPath -Directory |
  Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName "SKILL.md") } |
  Sort-Object Name

if (-not $skillDirs -or $skillDirs.Count -eq 0) {
  throw "No skill folders (with SKILL.md) found in $RepoPath"
}

$created = 0
$updated = 0
$unchanged = 0
$skipped = 0

foreach ($dir in $skillDirs) {
  $name = $dir.Name
  $src = (Resolve-AbsolutePath -PathValue $dir.FullName)
  $dst = Join-Path $SkillsDir $name

  if (Test-Path -LiteralPath $dst) {
    $item = Get-Item -LiteralPath $dst -Force
    if ($item.LinkType -eq "SymbolicLink" -or $item.LinkType -eq "Junction") {
      $targetRaw = $item.Target
      $targetResolved = $null
      try {
        $targetResolved = Resolve-AbsolutePath -PathValue $dst
      } catch {
        $targetResolved = $targetRaw
      }

      if ($targetResolved -eq $src -or $targetRaw -eq $src) {
        $unchanged++
        Write-Host "[ok] $name already linked"
      } elseif ($RefreshLinks) {
        $createdType = Update-SkillLink -DestinationPath $dst -SourcePath $src
        $updated++
        Write-Host "[updated] $name -> $src ($createdType)"
      } else {
        $skipped++
        Write-Host "[skip] $name has different link target ($targetRaw). Use -RefreshLinks to repoint."
      }
    } else {
      $skipped++
      Write-Host "[skip] $name destination exists and is not a link: $dst"
    }
  } else {
    $createdType = New-SkillLink -DestinationPath $dst -SourcePath $src
    $created++
    Write-Host "[created] $name -> $src ($createdType)"
  }
}

Write-Host ""
Write-Host "Sync summary:"
Write-Host "  created:   $created"
Write-Host "  updated:   $updated"
Write-Host "  unchanged: $unchanged"
Write-Host "  skipped:   $skipped"
