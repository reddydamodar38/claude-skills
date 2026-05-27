param(
  [Parameter(Mandatory = $true)][string]$ScriptName,
  [Parameter(ValueFromRemainingArguments = $true)][string[]]$ScriptArgs
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($ScriptName)) {
  throw "ScriptName is required."
}

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
  & $resolvedTargetPath @ScriptArgs
} else {
  & $resolvedTargetPath
}
