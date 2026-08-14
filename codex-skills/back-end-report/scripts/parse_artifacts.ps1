param(
    [Parameter(Mandatory=$true)][string]$RunPath,
    [Parameter(Mandatory=$true)][ValidateSet('baseline','current')][string]$RunName,
    [Parameter(Mandatory=$true)][string]$OutputPath
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'parser_core.ps1')

function Has-ReparsePoint([string]$Path, [string]$Root) {
    $current = Get-Item -LiteralPath $Path -Force
    while ($current -and $current.FullName.StartsWith($Root, [StringComparison]::OrdinalIgnoreCase)) {
        if (($current.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { return $true }
        $current = $current.Parent
    }
    $false
}

$resolved = (Resolve-Path -LiteralPath $RunPath).ProviderPath
$files = @(Get-ChildItem -LiteralPath $resolved -Recurse -File -Force |
    Where-Object { -not (Has-ReparsePoint $_.FullName $resolved) } |
    Sort-Object @{e={$_.FullName.Substring($resolved.Length).TrimStart('\').ToLowerInvariant()}}, FullName)
if (!$files.Count) { throw "No files found under run root: $resolved" }

$seen = @{}
$inventory = New-Object Collections.Generic.List[object]
$records = New-Object Collections.Generic.List[object]
$errors = New-Object Collections.Generic.List[object]
$entries = New-Object Collections.Generic.List[object]

foreach ($file in $files) {
    $relativePath = $file.FullName.Substring($resolved.Length).TrimStart('\')
    $parts = $relativePath -split '\\'
    $node = if ($parts.Count -gt 1) { $parts[0].ToUpperInvariant() } else { '(ROOT)' }
    $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    $fragment = Invoke-ArtifactParse -File $file -RelativePath $relativePath -Node $node -RunName $RunName -Sha256 $hash
    foreach ($item in @($fragment.inventory)) {
        $duplicate = $seen.ContainsKey($hash)
        if (!$duplicate) { $seen[$hash] = $relativePath }
        $item.is_duplicate = $duplicate
        $item.duplicate_of = if ($duplicate) { $seen[$hash] } else { $null }
        $inventory.Add($item)
    }
    foreach ($record in @($fragment.records)) { $records.Add($record) }
    foreach ($entry in @($fragment.zip_entries)) { $entries.Add($entry) }
    foreach ($errorItem in @($fragment.errors)) { $errors.Add($errorItem) }
}

$document = [ordered]@{
    run = $RunName
    path = $resolved
    inventory = $inventory.ToArray()
    records = $records.ToArray()
    zip_entries = $entries.ToArray()
    errors = $errors.ToArray()
}
$parent = Split-Path -Parent $OutputPath
if ($parent) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
$document | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
