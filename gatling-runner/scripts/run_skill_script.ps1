param(
  [Parameter(Mandatory=$true)][string]$ScriptName,
  [Parameter(ValueFromRemainingArguments=$true)][string[]]$ScriptArgs
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($ScriptName)) {
  throw "ScriptName is required."
}

# Restrict execution to scripts in this skill's scripts folder.
$scriptsDir = $PSScriptRoot
$targetPath = Join-Path $scriptsDir $ScriptName

if (-not ($targetPath.ToLowerInvariant().EndsWith(".ps1"))) {
  throw "Only .ps1 scripts are allowed."
}

if (-not (Test-Path $targetPath)) {
  throw "Script not found: $targetPath"
}

$resolvedScriptsDir = (Resolve-Path $scriptsDir).Path
$resolvedTargetPath = (Resolve-Path $targetPath).Path
if (-not $resolvedTargetPath.StartsWith($resolvedScriptsDir, [System.StringComparison]::OrdinalIgnoreCase)) {
  throw "Script path escapes skill scripts directory."
}

Write-Host "Executing skill script: $resolvedTargetPath"
if ($null -ne $ScriptArgs -and $ScriptArgs.Count -gt 0) {
  # Support documented launcher usage that includes a standalone "--".
  if ($ScriptArgs[0] -eq "--") {
    if ($ScriptArgs.Count -gt 1) {
      $ScriptArgs = $ScriptArgs[1..($ScriptArgs.Count - 1)]
    } else {
      $ScriptArgs = @()
    }
  }
  & pwsh -NoProfile -File $resolvedTargetPath @ScriptArgs
  if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
  }
} else {
  & pwsh -NoProfile -File $resolvedTargetPath
  if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
  }
}
