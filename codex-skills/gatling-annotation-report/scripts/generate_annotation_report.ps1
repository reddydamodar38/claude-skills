param(
  [Parameter(Mandatory=$true)]
  [string]$ScenarioDataPath,
  [Parameter(Mandatory=$true)]
  [string[]]$RepliesYamlPaths,
  [Parameter(Mandatory=$true)]
  [string]$OutputHtmlPath
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $ScenarioDataPath)) {
  throw "scenario-data.yaml not found: $ScenarioDataPath"
}

$scenarioYamlPath = Join-Path (Split-Path -Parent $ScenarioDataPath) "scenario.yaml"
$existingReplies = @($RepliesYamlPaths | Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and (Test-Path -LiteralPath $_) })
if ($existingReplies.Count -eq 0) {
  throw "No replies yaml files found from provided paths."
}

$lines = Get-Content -LiteralPath $ScenarioDataPath
$pairs = @()
for ($i = 0; $i -lt $lines.Count; $i++) {
  # Support both quoted and unquoted YAML param names:
  # - name: "foo"
  # - name: foo
  if ($lines[$i] -match '^\s*- name:\s*"?([^"\s]+)"?\s*$') {
    $name = $Matches[1]
    $path = ''
    for ($j = $i + 1; $j -lt [Math]::Min($i + 12, $lines.Count); $j++) {
      # Support both quoted and unquoted YAML annotation values:
      # value: ${Tx_1_0.instanceJson.x}
      # value: "${Tx_1_0.instanceJson.x}"
      if ($lines[$j] -match '^\s*value:\s*"?(\$\{[^}]+\})"?\s*$') { $path = $Matches[1]; break }
      if ($lines[$j] -match '^\s*- name: ') { break }
    }
    if ($path -ne '') {
      $pairs += [pscustomobject]@{ Name = $name; Path = $path }
    }
  }
}

$dedup = $pairs | Group-Object Name, Path | ForEach-Object {
  [pscustomobject]@{
    Name = $_.Group[0].Name
    Path = $_.Group[0].Path
    Count = $_.Count
  }
}

$replyLines = Get-Content -LiteralPath $existingReplies[0]
$transStarts = Select-String -Path $existingReplies[0] -Pattern '^\s*- transName: "([^"]+)"\s*$'
$transInfo = @{}
for ($i = 0; $i -lt $transStarts.Count; $i++) {
  $lineNum = $transStarts[$i].LineNumber
  $transName = [regex]::Match($transStarts[$i].Line, '^\s*- transName: "([^"]+)"\s*$').Groups[1].Value
  $nextLine = if ($i -lt $transStarts.Count - 1) { $transStarts[$i + 1].LineNumber } else { $replyLines.Count + 1 }
  $replyBodyLine = $lineNum + 1
  if ($replyBodyLine -le $replyLines.Count -and $replyLines[$replyBodyLine - 1] -match '^\s*replyBody:\s*\|-$') {
    $contentStart = $replyBodyLine + 1
    $contentEnd = $nextLine - 1
    for ($ln = $contentStart; $ln -le $nextLine - 1; $ln++) {
      $line = $replyLines[$ln - 1]
      if (($line -ne '') -and (-not $line.StartsWith('      '))) { $contentEnd = $ln - 1; break }
    }
    $transInfo[$transName] = @($contentStart, $contentEnd)
  }
}

function Get-PathValue {
  param($root, [string]$path)
  $cur = $root
  foreach ($seg in ($path -split '\.')) {
    $tmp = $seg
    while ($true) {
      $mm = [regex]::Match($tmp, '^([^\[]+)(\[(\d+)\])?(.*)$')
      if (-not $mm.Success) { return $null }
      $name = $mm.Groups[1].Value
      $idxText = $mm.Groups[3].Value
      $rest = $mm.Groups[4].Value
      if ($name -ne '') { try { $cur = $cur.$name } catch { return $null } }
      if ($idxText -ne '') { try { $cur = $cur[[int]$idxText] } catch { return $null } }
      if ([string]::IsNullOrEmpty($rest)) { break } else { $tmp = $rest }
    }
  }
  return $cur
}

$cache = @{}
$valueByPath = @{}
foreach ($p in ($dedup.Path | Sort-Object -Unique)) {
  if ($p -notmatch '^\$\{([^}]+)\}$') { $valueByPath[$p] = '<INVALID_PATH>'; continue }
  $ann = $Matches[1]
  $tx = ($ann -split '\.')[0]
  $actual = '<NULL_OR_NOT_FOUND>'

  if ($transInfo.ContainsKey($tx)) {
    if (-not $cache.ContainsKey($tx)) {
      $bounds = $transInfo[$tx]
      $buf = New-Object System.Collections.Generic.List[string]
      for ($k = $bounds[0] - 1; $k -le $bounds[1] - 1; $k++) {
        $line = $replyLines[$k]
        if ($line.StartsWith('      ')) { $buf.Add($line.Substring(6)) } else { $buf.Add($line) }
      }
      try { $cache[$tx] = (($buf -join "`n") | ConvertFrom-Json -Depth 300) } catch { $cache[$tx] = $null }
    }

    $obj = $cache[$tx]
    if ($null -ne $obj) {
      $pathOnly = $ann.Substring($tx.Length + 1)
      $v = Get-PathValue -root $obj -path $pathOnly
      if ($null -ne $v) {
        if ($v -is [string] -or $v.GetType().IsPrimitive) { $actual = [string]$v } else { $actual = ($v | ConvertTo-Json -Compress -Depth 20) }
      }
    }
  }

  $valueByPath[$p] = $actual
}

$rows = @()
foreach ($d in $dedup) {
  $ann = if ($d.Path -match '^\$\{([^}]+)\}$') { $Matches[1] } else { '' }
  $tx = if ($ann -ne '') { ($ann -split '\.')[0] } else { '' }
  $txNum = if ($tx -match '.*_(\d+)_\d+$') { [int]$Matches[1] } else { 999999 }
  $rows += [pscustomobject]@{
    TxNum = $txNum
    Name = $d.Name
    Path = $d.Path
    Value = $valueByPath[$d.Path]
    Count = $d.Count
  }
}
$rows = $rows | Sort-Object TxNum, Name, Path

$scenarioRefs = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
if (Test-Path -LiteralPath $scenarioYamlPath) {
  $scenarioRaw = Get-Content -Raw -LiteralPath $scenarioYamlPath
  foreach ($m in [regex]::Matches($scenarioRaw, '\$\{([^}]+)\}')) {
    $token = $m.Groups[1].Value
    if (-not [string]::IsNullOrWhiteSpace($token)) {
      [void]$scenarioRefs.Add($token.Trim())
    }
  }
}

$unusedRows = @()
foreach ($r in $rows) {
  if (-not $scenarioRefs.Contains([string]$r.Name)) {
    $unusedRows += [pscustomobject]@{
      Name = $r.Name
      Path = $r.Path
      Count = $r.Count
    }
  }
}
$unusedRows = $unusedRows | Sort-Object Name, Path

$idx = 1
$indexed = @()
foreach ($r in $rows) {
  $indexed += [pscustomobject]@{ Index = $idx; Name = $r.Name; Path = $r.Path; Value = $r.Value; Count = $r.Count }
  $idx++
}

$unusedIdx = 1
$unusedIndexed = @()
foreach ($u in $unusedRows) {
  $unusedIndexed += [pscustomobject]@{
    Index = $unusedIdx
    Name = $u.Name
    Path = $u.Path
    Count = $u.Count
  }
  $unusedIdx++
}

function E([string]$s) { [System.Net.WebUtility]::HtmlEncode($s) }
$generated = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss zzz')
$rowsHtml = ($indexed | ForEach-Object {
  '<tr><td>' + (E ([string]$_.Index)) + '</td><td>' + (E $_.Name) + '</td><td>' + (E $_.Path) + '</td><td>' + (E ([string]$_.Value)) + '</td><td>' + (E ([string]$_.Count)) + '</td></tr>'
}) -join "`n"

$unusedRowsHtml = ($unusedIndexed | ForEach-Object {
  '<tr><td>' + (E ([string]$_.Index)) + '</td><td>' + (E $_.Name) + '</td><td>' + (E $_.Path) + '</td><td>' + (E ([string]$_.Count)) + '</td></tr>'
}) -join "`n"

$html = @"
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Annotation Values Report</title>
  <style>
    body { font-family: Segoe UI, Arial, sans-serif; margin: 20px; color: #1f2937; }
    h1 { margin: 0 0 8px 0; }
    .meta { margin: 0 0 16px 0; color: #4b5563; }
    table { border-collapse: collapse; width: 100%; font-size: 12px; }
    th, td { border: 1px solid #d1d5db; padding: 6px 8px; text-align: left; vertical-align: top; }
    th { background: #f3f4f6; position: sticky; top: 0; }
    tr:nth-child(even) { background: #fafafa; }
    .mono { font-family: Consolas, 'Courier New', monospace; }
  </style>
</head>
<body>
  <h1>Annotation Values Report</h1>
  <p class="meta">Generated: $generated<br/>Columns: index, name, path, actual value, count<br/>Ordered by transaction number</p>
  <table>
    <thead><tr><th>Index</th><th>Name</th><th>Path</th><th>Actual Value</th><th>Count</th></tr></thead>
    <tbody class="mono">$rowsHtml</tbody>
  </table>
  <h2>Annotations In scenario-data.yaml But Not Used In scenario.yaml</h2>
  <p class="meta">Compared annotation names from scenario-data.yaml against all \${...} references in scenario.yaml.</p>
  <table>
    <thead><tr><th>Index</th><th>Name</th><th>Path</th><th>Count</th></tr></thead>
    <tbody class="mono">$unusedRowsHtml</tbody>
  </table>
</body>
</html>
"@

$parent = Split-Path -Parent $OutputHtmlPath
if (-not (Test-Path -LiteralPath $parent)) {
  New-Item -ItemType Directory -Path $parent -Force | Out-Null
}

Set-Content -LiteralPath $OutputHtmlPath -Value $html -Encoding UTF8
Write-Host "Generated annotation report: $OutputHtmlPath"
Write-Host "Unique rows: $($indexed.Count), total source rows: $($pairs.Count)"
Write-Host "Unused annotations (scenario-data vs scenario.yaml): $($unusedIndexed.Count)"
