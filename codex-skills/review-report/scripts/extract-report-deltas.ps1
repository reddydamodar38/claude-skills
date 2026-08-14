param(
    [Parameter(Mandatory = $true)]
    [string]$Path,

    [double]$ServicePercentThreshold = 5,
    [double]$AppCpuSecondsThreshold = 100,
    [double]$AppMemoryMiBThreshold = 50,
    [double]$CitrixCpuMsThreshold = 200,
    [double]$RtmsAverageMsThreshold = 500
)

$ErrorActionPreference = "Stop"

function Convert-ToNumber {
    param([object]$Value)
    if ($null -eq $Value) { return 0.0 }
    $text = [string]$Value
    $text = $text -replace ",", ""
    $text = $text -replace "%", ""
    $text = $text -replace "Increased", ""
    $text = $text -replace "Reduced", ""
    $text = $text.Trim()
    if ($text -eq "" -or $text -eq "-") { return 0.0 }
    $parsed = 0.0
    if ([double]::TryParse($text, [ref]$parsed)) { return $parsed }
    return 0.0
}

function Get-AttributeValue {
    param(
        [string]$Attributes,
        [string]$Name,
        [string]$Default = "1"
    )
    $pattern = "(?i)\b$Name\s*=\s*[""']?([^""'\s>]+)"
    $match = [regex]::Match($Attributes, $pattern)
    if ($match.Success) { return $match.Groups[1].Value }
    return $Default
}

function Clean-HtmlCell {
    param([string]$Html)
    $text = [regex]::Replace($Html, "(?is)<script.*?</script>", " ")
    $text = [regex]::Replace($text, "(?is)<style.*?</style>", " ")
    $text = [regex]::Replace($text, "(?is)<[^>]+>", " ")
    $text = [System.Net.WebUtility]::HtmlDecode($text)
    $text = $text -replace "\s+", " "
    return $text.Trim()
}

function Convert-HtmlTable {
    param([string]$TableHtml)

    $rows = New-Object System.Collections.Generic.List[object]
    $spans = @{}
    $trMatches = [regex]::Matches($TableHtml, "(?is)<tr[^>]*>(.*?)</tr>")

    foreach ($tr in $trMatches) {
        $rowMap = @{}

        foreach ($key in @($spans.Keys | Sort-Object {[int]$_})) {
            $span = $spans[$key]
            if ($span.Remain -gt 0) {
                $rowMap[[int]$key] = $span.Text
                $span.Remain = $span.Remain - 1
                if ($span.Remain -le 0) {
                    $spans.Remove($key)
                } else {
                    $spans[$key] = $span
                }
            }
        }

        $cellMatches = [regex]::Matches($tr.Groups[1].Value, "(?is)<(th|td)([^>]*)>(.*?)</(th|td)>")
        $column = 0

        foreach ($cell in $cellMatches) {
            while ($rowMap.ContainsKey($column)) { $column++ }

            $attributes = $cell.Groups[2].Value
            $rowspan = [int](Get-AttributeValue $attributes "rowspan" "1")
            $colspan = [int](Get-AttributeValue $attributes "colspan" "1")
            $text = Clean-HtmlCell $cell.Groups[3].Value

            for ($offset = 0; $offset -lt $colspan; $offset++) {
                $targetColumn = $column + $offset
                $rowMap[$targetColumn] = $text
                if ($rowspan -gt 1) {
                    $spans[[string]$targetColumn] = [pscustomobject]@{
                        Text = $text
                        Remain = $rowspan - 1
                    }
                }
            }

            $column += $colspan
        }

        if ($rowMap.Count -eq 0) {
            $rows.Add(@())
            continue
        }

        $maxColumn = ($rowMap.Keys | Measure-Object -Maximum).Maximum
        $row = for ($i = 0; $i -le $maxColumn; $i++) {
            if ($rowMap.ContainsKey($i)) { $rowMap[$i] } else { "" }
        }
        $rows.Add(@($row))
    }

    $output = @()
    foreach ($item in $rows) {
        $output += ,$item
    }
    return $output
}

function Get-TableRows {
    param(
        [object[]]$Tables,
        [int]$Index,
        [int]$Skip = 3
    )
    if ($Tables.Count -le $Index) { return @() }
    return @($Tables[$Index] | Select-Object -Skip $Skip)
}

$html = Get-Content -LiteralPath $Path -Raw
$tableMatches = [regex]::Matches($html, "(?is)<table[^>]*>.*?</table>")
$tables = foreach ($match in $tableMatches) { ,(Convert-HtmlTable $match.Value) }

$eggplant = foreach ($row in Get-TableRows $tables 3) {
    if ($row.Count -ge 11 -and $row[0]) {
        [pscustomobject]@{
            Workflow = $row[0]
            BaselineRate = $row[5]
            CurrentRate = $row[10]
            BaselineSuccess = $row[2]
            BaselineFailures = $row[3]
            CurrentSuccess = $row[7]
            CurrentFailures = $row[8]
            CurrentTotal = $row[9]
        }
    }
}

$service = foreach ($row in Get-TableRows $tables 5) {
    if ($row.Count -ge 8 -and (Convert-ToNumber $row[7]) -ge $ServicePercentThreshold) {
        [pscustomobject]@{
            Scenario = $row[0]
            BaselineMeanMs = $row[3]
            CurrentMeanMs = $row[6]
            DifferencePercent = $row[7]
            BaselineSuccessRate = $row[2]
            CurrentSuccessRate = $row[5]
        }
    }
}

$scpCpu = foreach ($row in Get-TableRows $tables 6) {
    if ($row.Count -ge 24) {
        $diffCpu = Convert-ToNumber $row[21]
        $diffMsg = Convert-ToNumber $row[20]
        if ($diffCpu -ge $AppCpuSecondsThreshold -or ($diffCpu -ge 40 -and $diffMsg -le 0)) {
            [pscustomobject]@{
                EntryId = $row[0]
                Name = $row[1]
                BaselineMessages = $row[4]
                CurrentMessages = $row[12]
                MessageDifference = $row[20]
                BaselineCpuSeconds = $row[5]
                CurrentCpuSeconds = $row[13]
                CpuDifferenceSeconds = $row[21]
            }
        }
    }
}

$scpMemory = foreach ($row in Get-TableRows $tables 6) {
    if ($row.Count -ge 24) {
        $diffPss = Convert-ToNumber $row[22]
        $diffRss = Convert-ToNumber $row[23]
        if ($diffPss -ge $AppMemoryMiBThreshold -or $diffRss -ge $AppMemoryMiBThreshold) {
            [pscustomobject]@{
                EntryId = $row[0]
                Name = $row[1]
                BaselineRssMiB = $row[9]
                CurrentRssMiB = $row[17]
                RssDifferenceMiB = $row[23]
                BaselinePssMiB = $row[8]
                CurrentPssMiB = $row[16]
                PssDifferenceMiB = $row[22]
            }
        }
    }
}

$windowsProcess = foreach ($row in Get-TableRows $tables 7) {
    if ($row.Count -ge 12 -and $row[0] -eq "windowssessionmonitor.exe") {
        [pscustomobject]@{
            Process = $row[0]
            BaselineCpuMs = $row[2]
            CurrentCpuMs = $row[6]
            CpuDifferencePercent = $row[10]
            BaselineProcessCount = $row[1]
            CurrentProcessCount = $row[5]
        }
    }
}

$workflowCpu = foreach ($row in Get-TableRows $tables 14) {
    if ($row.Count -ge 16 -and (Convert-ToNumber $row[15]) -ge $CitrixCpuMsThreshold) {
        [pscustomobject]@{
            Workflow = $row[0]
            Process = $row[1]
            BaselinePerIterationMs = $row[7]
            CurrentPerIterationMs = $row[13]
            DifferencePerIterationMs = $row[15]
            BaselineSuccessPercent = $row[5]
            CurrentSuccessPercent = $row[11]
        }
    }
}

$rtms = foreach ($row in Get-TableRows $tables 16) {
    if ($row.Count -ge 16 -and (Convert-ToNumber $row[15]) -ge $RtmsAverageMsThreshold) {
        [pscustomobject]@{
            Workflow = $row[0]
            Timer = $row[1]
            BaselineAverageMs = $row[5]
            CurrentAverageMs = $row[10]
            DifferenceAverageMs = $row[15]
            BaselineCount = $row[2]
            CurrentCount = $row[7]
        }
    }
}

$result = [pscustomobject]@{
    Path = (Resolve-Path -LiteralPath $Path).Path
    Tests = if ($tables.Count -gt 23) { $tables[23] } else { @() }
    ExecutiveCpu = if ($tables.Count -gt 1) { $tables[1] } else { @() }
    ExecutiveMemory = if ($tables.Count -gt 2) { $tables[2] } else { @() }
    EggplantSuccessDrops = @($eggplant | Where-Object { $_.CurrentRate -and $_.CurrentRate -ne "100.0%" })
    ServiceTransactions = @($service | Sort-Object {[double](Convert-ToNumber $_.DifferencePercent)} -Descending)
    AppTierCpu = @($scpCpu | Sort-Object {[double](Convert-ToNumber $_.CpuDifferenceSeconds)} -Descending)
    AppTierMemory = @($scpMemory | Sort-Object {[double](Convert-ToNumber $_.RssDifferenceMiB)} -Descending)
    WindowsSessionMonitor = @($windowsProcess)
    CitrixWorkflowCpu = @($workflowCpu | Sort-Object {[double](Convert-ToNumber $_.DifferencePerIterationMs)} -Descending)
    DatabaseSummary = if ($tables.Count -gt 13) { $tables[13] } else { @() }
    RtmsTimers = @($rtms | Sort-Object {[double](Convert-ToNumber $_.DifferenceAverageMs)} -Descending)
}

$result | ConvertTo-Json -Depth 8
