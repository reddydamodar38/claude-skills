param(
  [Parameter(Mandatory=$true)][string[]]$ScenarioNames,
  [string]$LocalReportsDir = "C:/Users/prakash/Desktop/project/NBS/gatling/reports",
  [string]$OutputFileName = "Gatling-Combined-Summary.html",
  [string]$Title = "Gatling Combined Summary"
)

$ErrorActionPreference = "Stop"

function Escape-Html {
  param([string]$Value)
  return [System.Net.WebUtility]::HtmlEncode([string]$Value)
}

function Parse-ScenarioReport {
  param(
    [string]$ScenarioName,
    [string]$ReportsDir
  )

  $scenarioReportsDir = Join-Path $ReportsDir $ScenarioName
  $reportPath = $null
  $reportFileName = "$ScenarioName.html"

  if (Test-Path $scenarioReportsDir) {
    $latest = Get-ChildItem -Path $scenarioReportsDir -File -Filter "$ScenarioName-*.html" -ErrorAction SilentlyContinue |
      Sort-Object LastWriteTime -Descending |
      Select-Object -First 1
    if ($latest) {
      $reportPath = $latest.FullName
      $reportFileName = [System.IO.Path]::GetRelativePath($ReportsDir, $latest.FullName).Replace('\\','/')
    }
  }

  if (-not $reportPath) {
    $legacyReportPath = Join-Path $ReportsDir ("$ScenarioName.html")
    if (Test-Path $legacyReportPath) {
      $reportPath = $legacyReportPath
      $reportFileName = "$ScenarioName.html"
    }
  }

  if (-not $reportPath) {
    return [PSCustomObject]@{
      Scenario = $ScenarioName
      ReportPath = (Join-Path $scenarioReportsDir ("$ScenarioName-*.html"))
      ReportFileName = "$ScenarioName/$ScenarioName-*.html"
      Exists = $false
      TotalFailed = 0
      Rows = @()
    }
  }

  $raw = Get-Content -Path $reportPath -Raw
  $rows = New-Object System.Collections.Generic.List[object]

  # Supports current report row format:
  # <tr><td><a ...>Transaction</a></td><td><pre>KO/Error</pre></td><td><pre>replies.yaml</pre></td><td><pre>Recommendation</pre></td></tr>
  # Falls back if the report is from an older format.
  $fullRowMatches = [regex]::Matches(
    $raw,
    "<tr><td><a href='#.*?'>(.*?)</a></td><td><pre>(.*?)</pre></td><td><pre>(.*?)</pre></td><td><pre>(.*?)</pre></td></tr>",
    [System.Text.RegularExpressions.RegexOptions]::Singleline
  )
  if ($fullRowMatches.Count -eq 0) {
    $fullRowMatches = [regex]::Matches(
      $raw,
      "<tr><td><a href='#.*?'>(.*?)</a></td><td><pre>(.*?)</pre></td><td><pre>(.*?)</pre></td></tr>",
      [System.Text.RegularExpressions.RegexOptions]::Singleline
    )
  }
  if ($fullRowMatches.Count -eq 0) {
    $fullRowMatches = [regex]::Matches(
      $raw,
      "<tr><td><a href='#.*?'>(.*?)</a></td><td><pre>(.*?)</pre></td></tr>",
      [System.Text.RegularExpressions.RegexOptions]::Singleline
    )
  }

  foreach ($m in $fullRowMatches) {
    $tx = [System.Net.WebUtility]::HtmlDecode($m.Groups[1].Value).Trim()
    $ko = if ($m.Groups.Count -ge 3) { [System.Net.WebUtility]::HtmlDecode($m.Groups[2].Value).Trim() } else { "" }
    $replyState = if ($m.Groups.Count -ge 4) { [System.Net.WebUtility]::HtmlDecode($m.Groups[3].Value).Trim() } else { "" }
    $recommendation = if ($m.Groups.Count -ge 5) { [System.Net.WebUtility]::HtmlDecode($m.Groups[4].Value).Trim() } else { "" }
    if (-not [string]::IsNullOrWhiteSpace($tx)) {
      $rows.Add([PSCustomObject]@{
        Transaction = $tx
        Outcome = $ko
        RepliesState = $replyState
        Recommendation = $recommendation
      })
    }
  }

  $total = $rows.Count
  $totalMatch = [regex]::Match($raw, '<strong>Total Failed Entries:</strong>\s*(\d+)')
  if ($totalMatch.Success) {
    $total = [int]$totalMatch.Groups[1].Value
  }

  return [PSCustomObject]@{
    Scenario = $ScenarioName
    ReportPath = $reportPath
    ReportFileName = $reportFileName
    Exists = $true
    TotalFailed = $total
    Rows = $rows.ToArray()
  }
}

New-Item -ItemType Directory -Path $LocalReportsDir -Force | Out-Null

$parsed = @($ScenarioNames | ForEach-Object { Parse-ScenarioReport -ScenarioName $_ -ReportsDir $LocalReportsDir })
$totalFailedAll = ($parsed | Measure-Object -Property TotalFailed -Sum).Sum

$scenarioTableRows = @(
  $parsed | ForEach-Object {
    $scenarioEsc = Escape-Html $_.Scenario
    $status = if (-not $_.Exists) { "Missing report" } elseif ($_.TotalFailed -eq 0) { "No failures" } else { "Failures found" }
    $statusEsc = Escape-Html $status
    $link = if ($_.Exists) { "<a href='$([System.Net.WebUtility]::HtmlEncode($_.ReportFileName))'>$([System.Net.WebUtility]::HtmlEncode($_.ReportFileName))</a>" } else { "<code>$([System.Net.WebUtility]::HtmlEncode($_.ReportFileName))</code>" }
    "<tr><td>$scenarioEsc</td><td>$($_.TotalFailed)</td><td>$statusEsc</td><td>$link</td></tr>"
  }
) -join "`n"

$allRows = foreach ($p in $parsed) {
  foreach ($r in $p.Rows) {
    [PSCustomObject]@{
      Scenario = $p.Scenario
      Transaction = $r.Transaction
      Outcome = $r.Outcome
      RepliesState = $r.RepliesState
    }
  }
}

$topTxRows = @(
  $allRows |
    Group-Object Transaction |
    Sort-Object -Property Count, Name -Descending |
    Select-Object -First 40 |
    ForEach-Object {
      $sample = $_.Group | Select-Object -First 1
      "<tr><td>$([System.Net.WebUtility]::HtmlEncode($_.Name))</td><td>$($_.Count)</td><td><pre>$([System.Net.WebUtility]::HtmlEncode($sample.Outcome))</pre></td><td><pre>$([System.Net.WebUtility]::HtmlEncode($sample.RepliesState))</pre></td></tr>"
    }
) -join "`n"
if ([string]::IsNullOrWhiteSpace($topTxRows)) {
  $topTxRows = "<tr><td colspan='4'>No failed transactions found.</td></tr>"
}

$detailSections = @(
  $parsed | ForEach-Object {
    $scenarioEsc = Escape-Html $_.Scenario
    $rowsHtml = if ($_.Rows.Count -eq 0) {
      "<tr><td colspan='4'>No failed transactions found in scenario report.</td></tr>"
    } else {
      @(
        $_.Rows | ForEach-Object {
          "<tr><td>$([System.Net.WebUtility]::HtmlEncode($_.Transaction))</td><td><pre>$([System.Net.WebUtility]::HtmlEncode($_.Outcome))</pre></td><td><pre>$([System.Net.WebUtility]::HtmlEncode($_.RepliesState))</pre></td><td><pre>$([System.Net.WebUtility]::HtmlEncode($_.Recommendation))</pre></td></tr>"
        }
      ) -join "`n"
    }

@"
<section>
  <h3>$scenarioEsc</h3>
  <table>
    <thead>
      <tr>
        <th>Transaction</th>
        <th>KO / Error</th>
        <th>replies.yaml</th>
        <th>Recommendation</th>
      </tr>
    </thead>
    <tbody>
      $rowsHtml
    </tbody>
  </table>
</section>
"@
  }
) -join "`n"

$generatedAt = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss zzz")
$titleEsc = Escape-Html $Title

$html = @"
<!DOCTYPE html>
<html lang='en'>
<head>
  <meta charset='UTF-8'>
  <title>$titleEsc</title>
  <style>
    body { font-family: Segoe UI, Arial, sans-serif; margin: 24px; color: #1f2937; }
    h1 { margin-bottom: 4px; }
    .meta { margin-bottom: 16px; color: #4b5563; }
    table { border-collapse: collapse; width: 100%; margin-bottom: 20px; }
    th, td { border: 1px solid #d1d5db; padding: 8px; vertical-align: top; font-size: 13px; }
    th { background: #f3f4f6; text-align: left; }
    pre { margin: 0; white-space: pre-wrap; word-wrap: break-word; font-family: Consolas, monospace; }
  </style>
</head>
<body>
  <h1>$titleEsc</h1>
  <div class='meta'>
    <div><strong>Generated:</strong> $generatedAt</div>
    <div><strong>Scenarios:</strong> $($ScenarioNames.Count)</div>
    <div><strong>Total Failed Entries (all reports):</strong> $totalFailedAll</div>
  </div>

  <h2>Scenario Overview</h2>
  <table>
    <thead>
      <tr>
        <th>Scenario</th>
        <th>Total Failed Entries</th>
        <th>Status</th>
        <th>Report Link</th>
      </tr>
    </thead>
    <tbody>
      $scenarioTableRows
    </tbody>
  </table>

  <h2>Top Repeated Failed Transactions</h2>
  <table>
    <thead>
      <tr>
        <th>Transaction</th>
        <th>Occurrences</th>
        <th>Sample KO / Error</th>
        <th>Sample replies.yaml</th>
      </tr>
    </thead>
    <tbody>
      $topTxRows
    </tbody>
  </table>

  <h2>Per Scenario Details</h2>
  $detailSections
</body>
</html>
"@

$outputPath = Join-Path $LocalReportsDir $OutputFileName
$html | Set-Content -Path $outputPath -Encoding UTF8
Write-Host "Combined summary report generated at: $outputPath"

