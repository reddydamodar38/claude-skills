param(
  [Parameter(Mandatory = $true)][string]$ScenarioName,
  [string]$TargetAlias = "ablfhir",
  [int]$MaxIterations = 20,
  [switch]$SkipFailedRepliesRemoval,
  [string]$ScriptRoot = "C:/Users/prakash/Desktop/project/NBS/gatling/script",
  [string]$ReportsRoot = "C:/Users/prakash/Desktop/project/NBS/gatling/reports",
  [string]$RunnerScriptPath = "",
  [string]$RunnerHostName = "",
  [string]$RunnerUserName = "",
  [string]$RunnerKeyPath = ""
)

$ErrorActionPreference = "Stop"

function Decode-Html {
  param([string]$Text)
  if ($null -eq $Text) { return "" }
  Add-Type -AssemblyName System.Web | Out-Null
  return [System.Web.HttpUtility]::HtmlDecode($Text)
}

function Get-ReportFailures {
  param([string]$ReportPath)

  if (-not (Test-Path -Path $ReportPath)) {
    throw "Report file not found: $ReportPath"
  }

  $html = Get-Content -Path $ReportPath -Raw
  $pattern = "(?is)<tr><td><a href='[^']*'>(?<tx>.*?)</a></td><td><pre>(?<ko>.*?)</pre></td><td><pre>(?<reply>.*?)</pre></td><td><pre>(?<rec>.*?)</pre></td></tr>"
  $matches = [regex]::Matches($html, $pattern)

  $rows = @()
  foreach ($m in $matches) {
    $tx = (Decode-Html $m.Groups["tx"].Value).Trim()
    $ko = (Decode-Html $m.Groups["ko"].Value).Trim()
    $reply = (Decode-Html $m.Groups["reply"].Value).Trim()
    $rec = (Decode-Html $m.Groups["rec"].Value).Trim()

    if ([string]::IsNullOrWhiteSpace($tx)) { continue }

    $reason = $null
    if ($reply -match "Failure in replies\.yaml") {
      $reason = "replies.yaml failure"
    } elseif ($ko -match "Failed to build request" -or $reply -match "Failed to build request" -or $rec -match "Failed to build request" -or $ko -match "YAML evaluation" -or $reply -match "YAML evaluation" -or $rec -match "YAML evaluation") {
      $reason = "request build failure"
    }

    if ($null -ne $reason) {
      $rows += [PSCustomObject]@{
        Transaction = $tx
        Reason = $reason
        KO = $ko
        Replies = $reply
        Recording = $rec
        Source = "html"
      }
    }
  }

  return $rows | Sort-Object Transaction, Reason -Unique
}

function Get-LatestScenarioReportPath {
  param(
    [Parameter(Mandatory = $true)][string]$ReportsDir,
    [Parameter(Mandatory = $true)][string]$Scenario
  )

  $scenarioReportDir = Join-Path $ReportsDir $Scenario
  if (Test-Path -Path $scenarioReportDir) {
    $latest = Get-ChildItem -Path $scenarioReportDir -File -Filter "$Scenario-*.html" -ErrorAction SilentlyContinue |
      Sort-Object LastWriteTime -Descending |
      Select-Object -First 1
    if ($latest) {
      return $latest.FullName
    }
  }

  $legacy = Join-Path $ReportsDir ($Scenario + ".html")
  if (Test-Path -Path $legacy) {
    return $legacy
  }

  return $null
}

function Get-LatestScenarioOutPath {
  param(
    [Parameter(Mandatory = $true)][string]$ReportsDir,
    [Parameter(Mandatory = $true)][string]$Scenario
  )

  $scenarioReportDir = Join-Path $ReportsDir $Scenario
  if (-not (Test-Path -Path $scenarioReportDir)) {
    return $null
  }

  $latest = Get-ChildItem -Path $scenarioReportDir -File -Filter "$Scenario-*.out" -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

  if ($latest) {
    return $latest.FullName
  }

  return $null
}

function Get-OutFailures {
  param([string]$OutPath)

  if (-not (Test-Path -Path $OutPath)) {
    return @()
  }

  $rows = @()
  $lines = Get-Content -Path $OutPath
  foreach ($line in $lines) {
    # Example:
    # > GetPatientAppointment_306_0: Failed to build request: ...
    $m = [regex]::Match($line, '^\s*>\s*(?<tx>[A-Za-z0-9_\-]+):\s*(?<msg>.+)$')
    if (-not $m.Success) { continue }

    $tx = $m.Groups["tx"].Value.Trim()
    $msg = $m.Groups["msg"].Value.Trim()
    if ([string]::IsNullOrWhiteSpace($tx) -or [string]::IsNullOrWhiteSpace($msg)) { continue }

    if ($msg -match 'Failure in replies\.yaml') {
      $rows += [PSCustomObject]@{
        Transaction = $tx
        Reason = "replies.yaml failure"
        Source = "out"
      }
      continue
    }

    if ($msg -match 'Failed to build request' -or $msg -match 'YAML evaluation') {
      $rows += [PSCustomObject]@{
        Transaction = $tx
        Reason = "request build failure"
        Source = "out"
      }
    }
  }

  # Distinct by transaction + reason
  return $rows | Sort-Object Transaction, Reason -Unique
}

function Get-TransactionOrder {
  param([string]$TransactionName)

  if ([string]::IsNullOrWhiteSpace($TransactionName)) { return [int]::MaxValue }
  $m = [regex]::Match($TransactionName, '_(\d+)_\d+$')
  if ($m.Success) {
    return [int]$m.Groups[1].Value
  }

  return [int]::MaxValue
}

function Get-TokensFromOutForTransaction {
  param(
    [Parameter(Mandatory = $true)][string]$OutPath,
    [Parameter(Mandatory = $true)][string]$TransactionName
  )

  if (-not (Test-Path -Path $OutPath)) { return @() }

  $escapedTx = [regex]::Escape($TransactionName)
  $linePattern = "^\s*>\s*$escapedTx\s*:\s*(?<msg>.+)$"
  $tokenPattern = '\$\{[^}]+\}'
  $tokens = New-Object System.Collections.Generic.List[string]

  foreach ($line in (Get-Content -Path $OutPath)) {
    $m = [regex]::Match($line, $linePattern)
    if (-not $m.Success) { continue }

    foreach ($tm in [regex]::Matches($m.Groups["msg"].Value, $tokenPattern)) {
      $tokens.Add($tm.Value) | Out-Null
    }
  }

  if ($tokens.Count -eq 0) { return @() }
  return @($tokens | Select-Object -Unique)
}

function Get-TokensFromHtmlForTransaction {
  param(
    [Parameter(Mandatory = $true)][object[]]$ReportFailures,
    [Parameter(Mandatory = $true)][string]$TransactionName
  )

  $tokenPattern = '\$\{[^}]+\}'
  $tokens = New-Object System.Collections.Generic.List[string]

  foreach ($row in $ReportFailures) {
    if (-not (Match-Transaction -ScenarioTx $TransactionName -ReportTx $row.Transaction)) { continue }

    $text = @(
      [string]$row.KO,
      [string]$row.Replies,
      [string]$row.Recording
    ) -join " "

    foreach ($tm in [regex]::Matches($text, $tokenPattern)) {
      $tokens.Add($tm.Value) | Out-Null
    }
  }

  if ($tokens.Count -eq 0) { return @() }
  return @($tokens | Select-Object -Unique)
}

function Get-ReplyJsonFromReplies {
  param(
    [Parameter(Mandatory = $true)][string]$RepliesPath,
    [Parameter(Mandatory = $true)][string]$TransactionName,
    [Parameter(Mandatory = $true)][hashtable]$ReplyCache
  )

  if ($ReplyCache.ContainsKey($TransactionName)) {
    return $ReplyCache[$TransactionName]
  }

  if (-not (Test-Path -Path $RepliesPath)) {
    $ReplyCache[$TransactionName] = $null
    return $null
  }

  $escapedTx = [regex]::Escape($TransactionName)
  $pattern = "(?ms)^\s*-\s*transName:\s*`"$escapedTx`"\s*\r?\n\s*replyBody:\s*\|-\s*\r?\n(?<body>(?:\s{6,}.*(?:\r?\n|$))*)"
  $raw = Get-Content -Path $RepliesPath -Raw
  $m = [regex]::Match($raw, $pattern)
  if (-not $m.Success) {
    $ReplyCache[$TransactionName] = $null
    return $null
  }

  $bodyLines = @()
  foreach ($line in ($m.Groups["body"].Value -split "`r?`n")) {
    if ($line -eq "") { continue }
    $bodyLines += ($line -replace '^\s{6}', '')
  }
  $jsonText = ($bodyLines -join "`n").Trim()
  if ([string]::IsNullOrWhiteSpace($jsonText)) {
    $ReplyCache[$TransactionName] = $null
    return $null
  }

  try {
    $obj = $jsonText | ConvertFrom-Json -Depth 100
    $ReplyCache[$TransactionName] = $obj
    return $obj
  } catch {
    $ReplyCache[$TransactionName] = $null
    return $null
  }
}

function Get-ObjectPropertyValue {
  param(
    [Parameter(Mandatory = $true)]$Object,
    [Parameter(Mandatory = $true)][string]$Name
  )

  if ($null -eq $Object) { return $null }
  if ($Object -is [System.Collections.IDictionary]) {
    if ($Object.Contains($Name)) { return $Object[$Name] }
    return $null
  }

  $prop = $Object.PSObject.Properties[$Name]
  if ($null -ne $prop) { return $prop.Value }
  return $null
}

function Resolve-TokenValueFromReplies {
  param(
    [Parameter(Mandatory = $true)][string]$Token,
    [Parameter(Mandatory = $true)][string]$RepliesPath,
    [Parameter(Mandatory = $true)][hashtable]$ReplyCache
  )

  $t = $Token.Trim()
  if (-not $t.StartsWith('${') -or -not $t.EndsWith('}')) {
    return [PSCustomObject]@{ Resolved = $false; Reason = "invalid token format" }
  }

  $inner = $t.Substring(2, $t.Length - 3)
  $dot = $inner.IndexOf('.')
  if ($dot -lt 1) {
    return [PSCustomObject]@{ Resolved = $false; Reason = "token has no source/path" }
  }

  $sourceTx = $inner.Substring(0, $dot)
  $path = $inner.Substring($dot + 1)
  if ([string]::IsNullOrWhiteSpace($sourceTx) -or [string]::IsNullOrWhiteSpace($path)) {
    return [PSCustomObject]@{ Resolved = $false; Reason = "token source/path empty" }
  }

  $replyObj = Get-ReplyJsonFromReplies -RepliesPath $RepliesPath -TransactionName $sourceTx -ReplyCache $ReplyCache
  if ($null -eq $replyObj) {
    return [PSCustomObject]@{ Resolved = $false; Reason = "source transaction not found in replies.yaml"; SourceTransaction = $sourceTx; Path = $path }
  }

  $current = $replyObj
  foreach ($segment in ($path -split '\.')) {
    if ([string]::IsNullOrWhiteSpace($segment)) {
      return [PSCustomObject]@{ Resolved = $false; Reason = "invalid empty path segment"; SourceTransaction = $sourceTx; Path = $path }
    }

    $nameMatch = [regex]::Match($segment, '^(?<name>[^\[]+)')
    if (-not $nameMatch.Success) {
      return [PSCustomObject]@{ Resolved = $false; Reason = "invalid path segment"; SourceTransaction = $sourceTx; Path = $path }
    }

    $propName = $nameMatch.Groups["name"].Value
    $current = Get-ObjectPropertyValue -Object $current -Name $propName
    if ($null -eq $current) {
      return [PSCustomObject]@{ Resolved = $false; Reason = "path not found"; SourceTransaction = $sourceTx; Path = $path }
    }

    $idxMatches = [regex]::Matches($segment, '\[(\d+)\]')
    foreach ($im in $idxMatches) {
      $idx = [int]$im.Groups[1].Value
      if (-not ($current -is [System.Collections.IList])) {
        return [PSCustomObject]@{ Resolved = $false; Reason = "path index on non-list"; SourceTransaction = $sourceTx; Path = $path }
      }
      if ($idx -lt 0 -or $idx -ge $current.Count) {
        return [PSCustomObject]@{ Resolved = $false; Reason = "path index out of bounds"; SourceTransaction = $sourceTx; Path = $path }
      }
      $current = $current[$idx]
    }
  }

  if ($null -eq $current) {
    return [PSCustomObject]@{ Resolved = $false; Reason = "resolved value is null"; SourceTransaction = $sourceTx; Path = $path }
  }

  if ($current -is [string] -or $current -is [ValueType]) {
    return [PSCustomObject]@{
      Resolved = $true
      SourceTransaction = $sourceTx
      Path = $path
      Value = [string]$current
    }
  }

  return [PSCustomObject]@{
    Resolved = $false
    Reason = "resolved value is non-scalar"
    SourceTransaction = $sourceTx
    Path = $path
  }
}

function Replace-TokenInScenarioFiles {
  param(
    [Parameter(Mandatory = $true)][string]$ScenarioDirectory,
    [Parameter(Mandatory = $true)][string]$Token,
    [Parameter(Mandatory = $true)][string]$Value
  )

  $targets = @(
    (Join-Path $ScenarioDirectory "scenario-data.yaml"),
    (Join-Path $ScenarioDirectory "scenario.yaml")
  )

  $escapedToken = [regex]::Escape($Token)
  $changed = New-Object System.Collections.Generic.List[object]

  foreach ($target in $targets) {
    if (-not (Test-Path -Path $target)) { continue }

    $text = Get-Content -Path $target -Raw
    $count = [regex]::Matches($text, $escapedToken).Count
    if ($count -le 0) { continue }

    $updated = [regex]::Replace($text, $escapedToken, [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $Value })
    if ($updated -ne $text) {
      [System.IO.File]::WriteAllText($target, $updated, [System.Text.Encoding]::UTF8)
      $changed.Add([PSCustomObject]@{
        File = $target
        Replacements = $count
      }) | Out-Null
    }
  }

  return @($changed)
}

function New-IterationScenarioBackups {
  param(
    [Parameter(Mandatory = $true)][string]$ScenarioDirectory,
    [Parameter(Mandatory = $true)][int]$Iteration
  )

  $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
  $files = @(Get-ChildItem -Path $ScenarioDirectory -File -Filter "scenario*.yaml" -ErrorAction SilentlyContinue)
  $created = New-Object System.Collections.Generic.List[string]

  foreach ($f in $files) {
    $backupPath = "$($f.FullName).autofix.v$Iteration-$timestamp.bak"
    Copy-Item -Path $f.FullName -Destination $backupPath -Force
    $created.Add($backupPath) | Out-Null
  }

  return @($created)
}

function Get-ScenarioTransactionBlocks {
  param([string]$ScenarioPath)

  $lines = Get-Content -Path $ScenarioPath
  $entries = @()

  for ($i = 0; $i -lt $lines.Count; $i++) {
    $line = $lines[$i]
    $m = [regex]::Match($line, '^(?<indent>\s*)-\s*transName:\s*"(?<name>[^"]+)"\s*$')
    if ($m.Success) {
      $entries += [PSCustomObject]@{
        Start = $i
        Indent = $m.Groups["indent"].Value.Length
        Name = $m.Groups["name"].Value
      }
    }
  }

  $blocks = @()
  for ($j = 0; $j -lt $entries.Count; $j++) {
    $start = $entries[$j].Start
    $end = if ($j -lt ($entries.Count - 1)) { $entries[$j + 1].Start - 1 } else { $lines.Count - 1 }
    $blocks += [PSCustomObject]@{
      Start = $start
      End = $end
      Name = $entries[$j].Name
    }
  }

  return [PSCustomObject]@{
    Lines = $lines
    Blocks = $blocks
  }
}

function Match-Transaction {
  param(
    [string]$ScenarioTx,
    [string]$ReportTx
  )

  if ([string]::IsNullOrWhiteSpace($ScenarioTx) -or [string]::IsNullOrWhiteSpace($ReportTx)) {
    return $false
  }

  $candidate = $ReportTx.Trim()
  if ($candidate.EndsWith("...")) {
    $prefix = $candidate.Substring(0, $candidate.Length - 3)
    return $ScenarioTx.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)
  }

  return $ScenarioTx.Equals($candidate, [System.StringComparison]::OrdinalIgnoreCase)
}

function Remove-FailedTransactions {
  param(
    [string]$ScenarioPath,
    [object[]]$Failures
  )

  $scenario = Get-ScenarioTransactionBlocks -ScenarioPath $ScenarioPath
  $lines = $scenario.Lines
  $blocks = $scenario.Blocks

  if ($blocks.Count -eq 0) {
    return [PSCustomObject]@{ Changed = $false; Removed = @() }
  }

  $removeRanges = New-Object System.Collections.Generic.List[object]
  $removed = New-Object System.Collections.Generic.List[object]

  foreach ($block in $blocks) {
    foreach ($failure in $Failures) {
      if (Match-Transaction -ScenarioTx $block.Name -ReportTx $failure.Transaction) {
        $removeRanges.Add([PSCustomObject]@{ Start = $block.Start; End = $block.End })
        $removed.Add([PSCustomObject]@{ Transaction = $block.Name; Reason = $failure.Reason })
        break
      }
    }
  }

  if ($removeRanges.Count -eq 0) {
    return [PSCustomObject]@{ Changed = $false; Removed = @() }
  }

  $drop = New-Object 'System.Collections.Generic.HashSet[int]'
  foreach ($r in $removeRanges) {
    for ($k = $r.Start; $k -le $r.End; $k++) {
      [void]$drop.Add($k)
    }
  }

  $out = New-Object System.Collections.Generic.List[string]
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if (-not $drop.Contains($i)) {
      $out.Add($lines[$i])
    }
  }

  [System.IO.File]::WriteAllLines($ScenarioPath, $out)

  return [PSCustomObject]@{
    Changed = $true
    Removed = $removed
  }
}

function Normalize-PatientTrackingListIndexZero {
  param(
    [Parameter(Mandatory = $true)][string]$ScenarioDirectory
  )

  $targets = @(
    (Join-Path $ScenarioDirectory "scenario-data.yaml"),
    (Join-Path $ScenarioDirectory "scenario.yaml")
  )

  $pattern = '(\$\{GetPatientTrackingApptListByCriteria_[^.}]+\.instanceJson\.patienttrackinglist\[)\d+(\])'
  $changes = New-Object System.Collections.Generic.List[object]

  foreach ($target in $targets) {
    if (-not (Test-Path -Path $target)) { continue }

    $text = [string](Get-Content -Path $target -Raw)
    $matchCount = [regex]::Matches($text, $pattern).Count
    if ($matchCount -le 0) { continue }

    $updated = ($text -replace $pattern, '${1}0$2')
    if ($updated -ne $text) {
      [System.IO.File]::WriteAllText($target, $updated, [System.Text.Encoding]::UTF8)
      $changes.Add([PSCustomObject]@{
        File = $target
        Replacements = $matchCount
      }) | Out-Null
    }
  }

  return @($changes)
}

$scenarioDir = Join-Path $ScriptRoot $ScenarioName
$scenarioPath = Join-Path $scenarioDir "scenario.yaml"
$scenarioReportDir = Join-Path $ReportsRoot $ScenarioName
$autoFixReportPath = Join-Path $scenarioReportDir ($ScenarioName + "-autofix-report.html")
$backupPath = $scenarioPath + ".autofix.bak"
$repliesPath = Join-Path $scenarioDir "replies.yaml"

if (-not (Test-Path -Path $scenarioPath)) {
  throw "scenario.yaml not found: $scenarioPath"
}
if (-not (Test-Path -Path $repliesPath)) {
  throw "replies.yaml not found: $repliesPath"
}

$runnerScript = $RunnerScriptPath
if ([string]::IsNullOrWhiteSpace($runnerScript)) {
  $runnerScript = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "gatling-runner/scripts/run_gatling_remote.ps1"
}
if (-not (Test-Path -Path $runnerScript)) {
  throw "gatling-runner script not found: $runnerScript"
}

if (-not (Test-Path -Path $backupPath)) {
  Copy-Item -Path $scenarioPath -Destination $backupPath -Force
}
New-Item -ItemType Directory -Path $scenarioReportDir -Force | Out-Null

$log = New-Object System.Collections.Generic.List[string]
$log.Add("# Gatling Auto Fix Report")
$log.Add("")
$log.Add("- Scenario: $ScenarioName")
$log.Add("- TargetAlias: $TargetAlias")
$log.Add("- MaxIterations: $MaxIterations")
$log.Add("- SkipFailedRepliesRemoval: $SkipFailedRepliesRemoval")
$log.Add("- Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')")
$log.Add("- scenario.yaml: $scenarioPath")
$log.Add("- replies.yaml: $repliesPath")
$log.Add("- Backup: $backupPath")
$log.Add("")
$fixesMade = New-Object System.Collections.Generic.List[object]
$replyCache = @{}

$indexFixes = @()
try {
  $indexFixes = Normalize-PatientTrackingListIndexZero -ScenarioDirectory $scenarioDir
} catch {
  $log.Add("- Index normalization step skipped due to error: $($_.Exception.Message)")
  $log.Add("")
}
if ($indexFixes.Count -gt 0) {
  $log.Add("- Applied index normalization fix for GetPatientTrackingApptListByCriteria_* -> patienttrackinglist[0]:")
  foreach ($fix in $indexFixes) {
    $log.Add("  - $($fix.File) (replacements: $($fix.Replacements))")
    $fixesMade.Add([PSCustomObject]@{
      Iteration = 0
      Type = "index-normalization"
      Target = $fix.File
      Detail = "patienttrackinglist index forced to [0], replacements=$($fix.Replacements)"
    }) | Out-Null
  }
  $log.Add("")
}

$stopReason = ""

for ($iter = 1; $iter -le $MaxIterations; $iter++) {
  $log.Add("## Iteration $iter")
  $log.Add("")
  $log.Add("Running gatling-runner...")

  try {
    $runnerArgs = @(
      "-ScenarioName", $ScenarioName,
      "-LocalScriptRoot", $ScriptRoot,
      "-LocalReportsDir", $ReportsRoot
    )
    if (-not [string]::IsNullOrWhiteSpace($TargetAlias)) {
      $runnerArgs += @("-TargetAlias", $TargetAlias)
    }
    if (-not [string]::IsNullOrWhiteSpace($RunnerHostName)) {
      $runnerArgs += @("-HostName", $RunnerHostName)
    }
    if (-not [string]::IsNullOrWhiteSpace($RunnerUserName)) {
      $runnerArgs += @("-UserName", $RunnerUserName)
    }
    if (-not [string]::IsNullOrWhiteSpace($RunnerKeyPath)) {
      $runnerArgs += @("-KeyPath", $RunnerKeyPath)
    }

    & $runnerScript @runnerArgs
    $log.Add("- Run status: success")
  } catch {
    $log.Add("- Run status: failed")
    $log.Add("- Run error: $($_.Exception.Message)")
    $stopReason = "runner failed"
    break
  }

  $iterationBackups = New-IterationScenarioBackups -ScenarioDirectory $scenarioDir -Iteration $iter
  if ($iterationBackups.Count -gt 0) {
    $log.Add("- Iteration backup(s):")
    foreach ($b in $iterationBackups) {
      $log.Add("  - $b")
    }
  } else {
    $log.Add("- Iteration backup(s): none (no scenario*.yaml files found)")
  }

  $reportPath = Get-LatestScenarioReportPath -ReportsDir $ReportsRoot -Scenario $ScenarioName
  if ([string]::IsNullOrWhiteSpace($reportPath)) {
    $log.Add("- No scenario report file found after runner execution.")
    $stopReason = "report file missing"
    break
  }
  $log.Add("- Using report: $reportPath")

  $outPath = Get-LatestScenarioOutPath -ReportsDir $ReportsRoot -Scenario $ScenarioName
  if (-not [string]::IsNullOrWhiteSpace($outPath)) {
    $log.Add("- Using out log: $outPath")
  } else {
    $log.Add("- No scenario out file found after runner execution.")
  }

  $reportFailures = Get-ReportFailures -ReportPath $reportPath
  $outFailures = @()
  if (-not [string]::IsNullOrWhiteSpace($outPath)) {
    $outFailures = Get-OutFailures -OutPath $outPath
  }

  $failures = @($reportFailures + $outFailures) | Sort-Object Transaction, Reason -Unique

  $buildOnly = @($failures | Where-Object { $_.Reason -eq "request build failure" })
  if ($buildOnly.Count -gt 0) {
    $log.Add("- Build/request failures detected from report/out: $($buildOnly.Count)")
    foreach ($b in $buildOnly) {
      $log.Add("  - $($b.Transaction) [$($b.Reason)]")
    }
  }

  $buildFixApplied = $false
  if ($buildOnly.Count -gt 0) {
    $orderedBuildFailures = @($buildOnly | Sort-Object @{Expression = { Get-TransactionOrder -TransactionName $_.Transaction }}, @{Expression = { $_.Transaction }})
    foreach ($bf in $orderedBuildFailures) {
      $tokens = @()
      if (-not [string]::IsNullOrWhiteSpace($outPath)) {
        $tokens = Get-TokensFromOutForTransaction -OutPath $outPath -TransactionName $bf.Transaction
      }
      if ($tokens.Count -eq 0) {
        $tokens = Get-TokensFromHtmlForTransaction -ReportFailures $reportFailures -TransactionName $bf.Transaction
      }
      if ($tokens.Count -eq 0) {
        $log.Add("- No token expression found in .out/.html for $($bf.Transaction); skipping.")
        continue
      }

      $tokenFixed = $false
      foreach ($token in $tokens) {
        $resolved = Resolve-TokenValueFromReplies -Token $token -RepliesPath $repliesPath -ReplyCache $replyCache
        if (-not $resolved.Resolved) {
          $log.Add("- Could not resolve token for $($bf.Transaction): $token ($($resolved.Reason))")
          continue
        }

        $changes = Replace-TokenInScenarioFiles -ScenarioDirectory $scenarioDir -Token $token -Value $resolved.Value
        if ($changes.Count -eq 0) {
          $log.Add("- Resolved token but no replacement sites found for $($bf.Transaction): $token")
          continue
        }

        $log.Add("- Applied request-build fix for $($bf.Transaction): $token -> $($resolved.Value)")
        foreach ($chg in $changes) {
          $log.Add("  - updated: $($chg.File) (replacements: $($chg.Replacements))")
        }
        $fixesMade.Add([PSCustomObject]@{
          Iteration = $iter
          Type = "replace-annotation"
          Target = $bf.Transaction
          Detail = "$token -> $($resolved.Value)"
        }) | Out-Null
        $buildFixApplied = $true
        $tokenFixed = $true
        break
      }

      if ($tokenFixed) { break }
    }
  }

  if ($buildFixApplied) {
    $log.Add("- Applied one request-build fix this iteration; rerunning next iteration.")
    $log.Add("")
    if ($iter -eq $MaxIterations) {
      $stopReason = "max iterations reached"
    }
    continue
  }

  $repliesFailures = @($failures | Where-Object { $_.Reason -eq "replies.yaml failure" })
  $failures = $repliesFailures
  if ($null -eq $failures -or $failures.Count -eq 0) {
    $log.Add("- No removable replies.yaml failures found in report/out (strict rule: only replies.yaml failures are removable).")
    if ($buildOnly.Count -gt 0) {
      $stopReason = "request build failures found in .out; no replies.yaml removals eligible"
    } else {
      $stopReason = "no replies.yaml failures to remove"
    }
    break
  }

  $log.Add("- Candidates from report: $($failures.Count)")
  foreach ($f in $failures) {
    $log.Add("  - $($f.Transaction) [$($f.Reason)]")
  }

  if ($SkipFailedRepliesRemoval) {
    $log.Add("- Skip flag enabled. No failed replies.yaml transactions were removed.")
    $stopReason = "replies.yaml removals skipped by option"
    break
  }

  $result = Remove-FailedTransactions -ScenarioPath $scenarioPath -Failures $failures
  if (-not $result.Changed) {
    $log.Add("- No matching transactions found in scenario.yaml for current candidates.")
    $stopReason = "no matching scenario transactions"
    break
  }

  $log.Add("- Removed from scenario.yaml: $($result.Removed.Count)")
  foreach ($r in $result.Removed) {
    $log.Add("  - $($r.Transaction) [$($r.Reason)]")
    $fixesMade.Add([PSCustomObject]@{
      Iteration = $iter
      Type = "remove-transaction"
      Target = $r.Transaction
      Detail = $r.Reason
    }) | Out-Null
  }

  $log.Add("")

  if ($iter -eq $MaxIterations) {
    $stopReason = "max iterations reached"
  }
}

if ([string]::IsNullOrWhiteSpace($stopReason)) {
  $stopReason = "completed"
}

$log.Add("")
$log.Add("## Stop Reason")
$log.Add("")
$log.Add("$stopReason")
$log.Add("")
$log.Add("## Fixes Made")
$log.Add("")
if ($fixesMade.Count -eq 0) {
  $log.Add("none")
} else {
  foreach ($fx in $fixesMade) {
    $log.Add("- Iteration $($fx.Iteration): $($fx.Type) -> $($fx.Target) ($($fx.Detail))")
  }
}
$log.Add("")
$log.Add("- Finished: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')")

$htmlBody = [System.Net.WebUtility]::HtmlEncode(($log -join [Environment]::NewLine))
$html = @"
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>Gatling Auto Fix Report - $ScenarioName</title>
  <style>
    body { font-family: Segoe UI, Arial, sans-serif; margin: 24px; color: #1f2937; }
    h1 { margin: 0 0 16px 0; font-size: 24px; }
    pre { background: #f8fafc; border: 1px solid #e5e7eb; border-radius: 8px; padding: 16px; white-space: pre-wrap; line-height: 1.45; }
  </style>
</head>
<body>
  <h1>Gatling Auto Fix Report</h1>
  <pre>$htmlBody</pre>
</body>
</html>
"@
[System.IO.File]::WriteAllText($autoFixReportPath, $html, [System.Text.Encoding]::UTF8)
Write-Host "Auto-fix report written: $autoFixReportPath"


