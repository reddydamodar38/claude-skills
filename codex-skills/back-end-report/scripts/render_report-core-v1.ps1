param(
    [Parameter(Mandatory = $true)][string]$DataPath,
    [string]$OutputPath,
    [string]$TemplatePath = (Join-Path $PSScriptRoot '..\assets\reference-workbook.xlsx'),
    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'workbook_helpers.ps1')

function Assert-Contract {
    param($Data)
    if ($Data.schema_version -ne '1.0') { throw 'schema_version must be 1.0' }
    foreach ($run in @('baseline','current')) {
        if (-not $Data.runs.$run.path) { throw "runs.$run.path is required" }
        if ($null -eq $Data.runs.$run.nodes) { throw "runs.$run.nodes is required" }
    }
    foreach ($name in @('limitations','node_summary','server_comparison','gc_comparison','smaps_end','config_changes','details')) {
        if ($null -eq $Data.report.$name) { throw "report.$name is required" }
    }
}

function Get-Value {
    param($Row, [string]$Name)
    $property = $Row.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Set-Table {
    param($Sheet, $Rows, [string[]]$Properties)
    $usedRows = [Math]::Max($Sheet.UsedRange.Rows.Count, 2)
    $Sheet.Range("A2:XFD$usedRows").ClearContents() | Out-Null
    for ($r = 0; $r -lt @($Rows).Count; $r++) {
        for ($c = 0; $c -lt $Properties.Count; $c++) {
            $value = Get-Value -Row @($Rows)[$r] -Name $Properties[$c]
            if ($Properties[$c] -eq 'assessment') { $value = Format-Assessment $value }
            if ($value -is [string] -and $value -match '^[=+\-@]') { $value = "'" + $value }
            if ($null -ne $value) { $Sheet.Cells.Item($r + 2, $c + 1).Value2 = $value }
        }
    }
}

$resolvedData = (Resolve-Path -LiteralPath $DataPath).Path
$data = Get-Content -Raw -LiteralPath $resolvedData | ConvertFrom-Json
Assert-Contract -Data $data

if ($ValidateOnly) {
    Write-Output 'PASS: canonical report JSON contract'
    exit 0
}

if (-not $OutputPath) { throw 'OutputPath is required unless ValidateOnly is used.' }
$excelType = [type]::GetTypeFromProgID('Excel.Application')
if ($null -eq $excelType) {
    throw 'Microsoft Excel automation is unavailable. Use a Codex spreadsheet runtime to render the same canonical JSON contract.'
}

$resolvedTemplate = (Resolve-Path -LiteralPath $TemplatePath).Path
$outputFull = [IO.Path]::GetFullPath($OutputPath)
$outputParent = Split-Path -Parent $outputFull
if ($outputParent) { New-Item -ItemType Directory -Path $outputParent -Force | Out-Null }
Copy-Item -LiteralPath $resolvedTemplate -Destination $outputFull -Force

$excel = $null
$book = $null
try {
    $excel = New-Object -ComObject Excel.Application
    $excel.Visible = $false
    $excel.DisplayAlerts = $false
    $book = $excel.Workbooks.Open($outputFull)

    $nodeProps = @('node','baseline_avg_rss_mb','current_avg_rss_mb','delta_avg_rss_mb','baseline_end_rss_mb','current_end_rss_mb','delta_end_rss_mb','baseline_avg_memavailable_mb','current_avg_memavailable_mb','delta_memavailable_mb','java_avg_rss_delta_mb')
    $serverProps = @('node','server_id','server_name','priority','configured_instances','observed_instances','xms_mb_per_jvm','xmx_mb_per_jvm','collector','gc_logging','baseline_avg_rss_mb','current_avg_rss_mb','delta_avg_rss_mb','baseline_end_rss_mb','current_end_rss_mb','delta_end_rss_mb','baseline_end_pss_mb','current_end_pss_mb','delta_pss_mb','delta_private_dirty_mb','delta_shared_clean_mb','baseline_final_after_gc_mb','current_final_after_gc_mb','delta_final_after_gc_mb','likely_cause','recommended_route','command')
    $gcProps = @('node','server_id','server_name','collector','baseline_logs','current_logs','baseline_gc_events','current_gc_events','delta_events','baseline_full_gc','current_full_gc','baseline_avg_pause_ms','current_avg_pause_ms','baseline_max_pause_ms','current_max_pause_ms','baseline_gc_overhead_pct','current_gc_overhead_pct','baseline_final_after_gc_mb','current_final_after_gc_mb','delta_after_gc_mb')
    $smapsProps = @('node','server_id','server_name','baseline_rss_mb','current_rss_mb','delta_rss_mb','baseline_pss_mb','current_pss_mb','delta_pss_mb','baseline_private_dirty_mb','current_private_dirty_mb','delta_private_dirty_mb','delta_shared_clean_mb','interpretation')
    $configProps = @('node','server_id','server_name','property','baseline','current')

    Set-Table $book.Worksheets.Item('Node Summary') $data.report.node_summary $nodeProps
    Set-Table $book.Worksheets.Item('Server Comparison') $data.report.server_comparison $serverProps
    Set-Table $book.Worksheets.Item('GC Comparison') $data.report.gc_comparison $gcProps
    Set-Table $book.Worksheets.Item('Smaps End') $data.report.smaps_end $smapsProps
    Set-Table $book.Worksheets.Item('Config Changes') $data.report.config_changes $configProps

    $readMe = $book.Worksheets.Item('Read Me')
    $readMe.Range('B7').Value2 = $data.runs.baseline.path
    $readMe.Range('B8').Value2 = $data.runs.current.path
    $readMe.Range('B9').Value2 = (@($data.report.limitations) -join '; ')

    $originalDetails = @()
    for ($i = 7; $i -le $book.Worksheets.Count; $i++) { $originalDetails += $book.Worksheets.Item($i).Name }
    $template = if ($originalDetails.Count) { $book.Worksheets.Item($originalDetails[0]) } else { $null }

    foreach ($detail in @($data.report.details)) {
        if ($null -eq $template) { throw 'The reference workbook has no detail-sheet template.' }
        $template.Copy([Type]::Missing, $book.Worksheets.Item($book.Worksheets.Count))
        $sheet = $book.Worksheets.Item($book.Worksheets.Count)
        $baseName = ("S{0} {1}" -f $detail.server_id, $detail.server_name) -replace '[:\\/\?\*\[\]]',' '
        if ($baseName.Length -gt 31) { $baseName = $baseName.Substring(0,31) }
        $candidate = $baseName
        $suffix = 2
        while (@($book.Worksheets | ForEach-Object Name) -contains $candidate) {
            $tail = "-$suffix"
            $candidate = $baseName.Substring(0, [Math]::Min($baseName.Length, 31 - $tail.Length)) + $tail
            $suffix++
        }
        $sheet.Name = $candidate
        $sheet.UsedRange.ClearContents() | Out-Null
        $sheet.Range('A1').Value2 = "Server $($detail.server_id): $($detail.server_name)"
        $headers = @('Node','Instances','Xms MB/JVM','Xmx MB/JVM','Avg RSS Delta MB','End PSS Delta MB','After-GC Delta MB','Assessment')
        for ($c=0; $c -lt $headers.Count; $c++) { $sheet.Cells.Item(3,$c+1).Value2 = $headers[$c] }
        $nodeProperties = @('node','instances','xms_mb_per_jvm','xmx_mb_per_jvm','avg_rss_delta_mb','end_pss_delta_mb','after_gc_delta_mb','assessment')
        for ($r=0; $r -lt @($detail.nodes).Count; $r++) {
            for ($c=0; $c -lt $nodeProperties.Count; $c++) {
                $value = Get-Value @($detail.nodes)[$r] $nodeProperties[$c]
                if ($nodeProperties[$c] -eq 'assessment') { $value = Format-Assessment $value }
                if ($value -is [string] -and $value -match '^[=+\-@]') { $value = "'" + $value }
                if ($null -ne $value) { $sheet.Cells.Item($r+4,$c+1).Value2 = $value }
            }
        }
        $sheet.Cells.Item(8,1).Value2 = 'Sample'
        $maxSamples = 0
        for ($s=0; $s -lt @($detail.series).Count; $s++) {
            $sheet.Cells.Item(8,$s+2).Value2 = $detail.series[$s].name
            $values = @($detail.series[$s].values)
            $maxSamples = [Math]::Max($maxSamples, $values.Count)
            for ($r=0; $r -lt $values.Count; $r++) { $sheet.Cells.Item($r+9,$s+2).Value2 = $values[$r] }
        }
        for ($r=1; $r -le $maxSamples; $r++) { $sheet.Cells.Item($r+8,1).Value2 = $r }
        $footerRow = [Math]::Max(23, $maxSamples + 10)
        $sheet.Cells.Item($footerRow,1).Value2 = 'Investigation route'
        $sheet.Cells.Item($footerRow,2).Value2 = $detail.investigation_route
        $sheet.Cells.Item($footerRow+1,1).Value2 = 'Command'
        $sheet.Cells.Item($footerRow+1,2).Value2 = $detail.command
        if ($sheet.ChartObjects().Count -gt 0 -and $maxSamples -gt 0) {
            $lastColumn = @($detail.series).Count + 1
            $source = $sheet.Range($sheet.Cells.Item(8,1), $sheet.Cells.Item($maxSamples+8,$lastColumn))
            $sheet.ChartObjects(1).Chart.SetSourceData($source)
            $sheet.ChartObjects(1).Chart.HasTitle = $true
            $sheet.ChartObjects(1).Chart.ChartTitle.Text = 'Aggregate server RSS across test samples'
        }
    }

    foreach ($name in $originalDetails) { $book.Worksheets.Item($name).Delete() }
    $book.Save()
    Write-Output "PASS: workbook rendered to $outputFull"
}
finally {
    if ($book) { $book.Close($true) | Out-Null }
    if ($excel) { $excel.Quit() }
    if ($book) { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($book) }
    if ($excel) { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($excel) }
    [GC]::Collect()
    [GC]::WaitForPendingFinalizers()
}

