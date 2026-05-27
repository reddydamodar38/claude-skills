param(
  [string]$ScenarioPath,
  [string]$InCsvPath,
  [Parameter(Mandatory = $true)][string]$RepliesPath,
  [Parameter(Mandatory = $true)][string]$OutCsvPath,
  [switch]$Unique
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Resolve-ObjectPath {
  param(
    [Parameter(Mandatory = $true)]$Root,
    [Parameter(Mandatory = $true)][string]$Path
  )
  $cur = $Root
  foreach ($part in ($Path -split '\.')) {
    if ($part -notmatch '^([A-Za-z0-9_\-]+)(?:\[(\d+)\])?$') { return $null }
    $key = $matches[1]
    $idx = $matches[2]

    if ($cur -is [pscustomobject]) {
      $prop = $cur.PSObject.Properties[$key]
      if ($null -eq $prop) { return $null }
      $cur = $prop.Value
    } elseif ($cur -is [System.Collections.IDictionary]) {
      if (-not $cur.Contains($key)) { return $null }
      $cur = $cur[$key]
    } else {
      return $null
    }

    if ($null -ne $idx -and $idx -ne "") {
      $i = [int]$idx
      if (-not ($cur -is [System.Collections.IList])) { return $null }
      if ($i -lt 0 -or $i -ge $cur.Count) { return $null }
      $cur = $cur[$i]
    }
  }
  return $cur
}

function Get-BaseRowsFromScenario {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [switch]$UniqueRows
  )
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "Scenario file not found: $Path"
  }

  $lines = Get-Content -LiteralPath $Path
  $rows = New-Object System.Collections.Generic.List[object]
  $seen = New-Object "System.Collections.Generic.HashSet[string]"
  $currentName = $null

  foreach ($line in $lines) {
    if ($line -match '^\s*-\s+name:\s+"([^"]+)"\s*$') {
      $currentName = $matches[1]
      continue
    }
    if ($null -ne $currentName -and $line -match '^\s+value:\s*(.+?)\s*$') {
      $value = $matches[1].Trim()
      if ($value -match '^"(.*)"$') { $value = $matches[1] }

      $key = "$currentName`t$value"
      if ($UniqueRows -and -not $seen.Add($key)) {
        $currentName = $null
        continue
      }

      $rows.Add([pscustomobject]@{
          name  = $currentName
          value = $value
        }) | Out-Null
      $currentName = $null
    }
  }
  return $rows
}

function Get-NeededTransactions {
  param([Parameter(Mandatory = $true)]$Rows)
  $needed = New-Object "System.Collections.Generic.HashSet[string]"
  foreach ($r in $Rows) {
    if ($r.value -match '^\$\{([^}]+)\}$') {
      $expr = $matches[1]
      $dot = $expr.IndexOf('.')
      if ($dot -gt 0) {
        [void]$needed.Add($expr.Substring(0, $dot))
      }
    }
  }
  return $needed
}

function Get-ReplyMap {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)]$NeededTrans
  )
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "Replies file not found: $Path"
  }

  $replyMap = @{}
  $lines = Get-Content -LiteralPath $Path
  $currentTrans = $null
  $collecting = $false
  $capture = $false
  $jsonLines = New-Object System.Collections.Generic.List[string]

  foreach ($line in $lines) {
    if ($collecting) {
      if ($line -match '^\s*-\s+transName:\s+"([^"]+)"\s*$') {
        if ($capture -and $jsonLines.Count -gt 0) {
          try { $replyMap[$currentTrans] = (($jsonLines -join "`n") | ConvertFrom-Json) } catch {}
        }
        $currentTrans = $matches[1]
        $capture = $NeededTrans.Contains($currentTrans)
        $jsonLines.Clear()
        $collecting = $false
        continue
      }
      if ($line -match '^\s{4}(.*)$') {
        if ($capture) { $jsonLines.Add($matches[1]) | Out-Null }
        continue
      }
      if ($capture -and $jsonLines.Count -gt 0) {
        try { $replyMap[$currentTrans] = (($jsonLines -join "`n") | ConvertFrom-Json) } catch {}
      }
      $jsonLines.Clear()
      $collecting = $false
    }

    if ($line -match '^\s*-\s+transName:\s+"([^"]+)"\s*$') {
      $currentTrans = $matches[1]
      $capture = $NeededTrans.Contains($currentTrans)
      continue
    }
    if ($line -match '^\s+replyBody:\s+\|-\s*$') {
      if ($null -ne $currentTrans) {
        $collecting = $true
        $jsonLines.Clear()
      }
      continue
    }
  }

  if ($collecting -and $capture -and $jsonLines.Count -gt 0) {
    try { $replyMap[$currentTrans] = (($jsonLines -join "`n") | ConvertFrom-Json) } catch {}
  }

  return $replyMap
}

if ([string]::IsNullOrWhiteSpace($InCsvPath) -and [string]::IsNullOrWhiteSpace($ScenarioPath)) {
  throw "Provide either -InCsvPath or -ScenarioPath."
}

$baseRows = @()
if (-not [string]::IsNullOrWhiteSpace($InCsvPath)) {
  if (-not (Test-Path -LiteralPath $InCsvPath -PathType Leaf)) {
    throw "Input CSV not found: $InCsvPath"
  }
  $imported = Import-Csv -LiteralPath $InCsvPath
  $baseRows = foreach ($r in $imported) {
    [pscustomobject]@{
      name  = $r.name
      value = $r.value
    }
  }
} else {
  $baseRows = Get-BaseRowsFromScenario -Path $ScenarioPath -UniqueRows:$Unique
}

$neededTrans = Get-NeededTransactions -Rows $baseRows
$replyMap = Get-ReplyMap -Path $RepliesPath -NeededTrans $neededTrans

$resolvedCount = 0
$outRows = foreach ($r in $baseRows) {
  $value1 = ""
  if ($r.value -match '^\$\{([^}]+)\}$') {
    $expr = $matches[1]
    $dot = $expr.IndexOf('.')
    if ($dot -gt 0) {
      $trans = $expr.Substring(0, $dot)
      $path = $expr.Substring($dot + 1)
      if ($replyMap.ContainsKey($trans)) {
        $val = Resolve-ObjectPath -Root $replyMap[$trans] -Path $path
        if ($null -ne $val) {
          if ($val -is [string] -or $val -is [ValueType]) {
            $value1 = [string]$val
          } else {
            $value1 = ($val | ConvertTo-Json -Compress -Depth 10)
          }
          $resolvedCount++
        }
      }
    }
  }
  [pscustomobject]@{
    name   = $r.name
    value  = $r.value
    value1 = $value1
  }
}

$outDir = Split-Path -Parent $OutCsvPath
if ($outDir -and -not (Test-Path -LiteralPath $outDir)) {
  New-Item -ItemType Directory -Path $outDir -Force | Out-Null
}

$outRows | Export-Csv -LiteralPath $OutCsvPath -NoTypeInformation -Encoding UTF8
Write-Output ("Wrote {0} rows to {1}. Resolved value1: {2}. Transactions loaded: {3}" -f $outRows.Count, $OutCsvPath, $resolvedCount, $replyMap.Keys.Count)
