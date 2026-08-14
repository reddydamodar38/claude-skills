$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$scratch = Join-Path $env:TEMP ('back-end-false-positive-' + [guid]::NewGuid().ToString('N'))
$priorConvertFunction = Get-Item -LiteralPath Function:\ConvertFrom-Csv -ErrorAction SilentlyContinue
$global:BackEndReportLongCsvConversionAttempted = $false

function global:ConvertFrom-Csv {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true,ValueFromPipeline=$true)][AllowEmptyString()][string]$InputObject)
    process {
        if ($InputObject.Length -gt 4096) {
            $global:BackEndReportLongCsvConversionAttempted = $true
            throw 'TEST GUARD: schema detection passed a long CSV string to ConvertFrom-Csv.'
        }
        Microsoft.PowerShell.Utility\ConvertFrom-Csv -InputObject $InputObject
    }
}

try {
    $run = Join-Path $scratch 'run'
    New-Item -ItemType Directory -Path $run -Force | Out-Null
    $artifact = Join-Path $run 'ELK_data.csv'
    @'
# Multi-section export
### Process RSS statistics
"'yyyy-mm-dd hh24:mi')","'yyyy-mm-dd hh24:mi')",RSS
2026-07-02,2026-07-02,100
'@ | Set-Content -LiteralPath $artifact
    Set-Content -LiteralPath (Join-Path $run 'ordered.csv') -Value "timestamp,server_id,pid,rss_mb,private_mb`n2026-07-03T00:00:00Z,S1,10,128,64"
    Set-Content -LiteralPath (Join-Path $run 'rss-spelling.csv') -Value "timestamp,pid,rss,server_id`n2026-07-03T00:00:00Z,20,256,S2"
    $genericRows = @('timestamp,value') + @(1..2000 | ForEach-Object { "2026-07-03T00:00:00Z,$_" })
    Set-Content -LiteralPath (Join-Path $run 'large-generic.csv') -Value $genericRows

    $parsed = Join-Path $scratch 'parsed.json'
    & "$root\scripts\parse_artifacts.ps1" -RunPath $run -RunName baseline -OutputPath $parsed
    $data = Get-Content -LiteralPath $parsed -Raw | ConvertFrom-Json
    $item = @($data.inventory | Where-Object relative_path -eq 'ELK_data.csv')
    if ($item.Count -ne 1) { throw 'ASSERT: ELK artifact must remain in inventory.' }
    if ($item[0].category -ne 'unknown') {
        throw "ASSERT: unsupported multi-section ELK artifact must be unknown, actual=$($item[0].category)."
    }
    $generic = @($data.inventory | Where-Object relative_path -eq 'large-generic.csv')
    if ($generic.Count -ne 1 -or $generic[0].category -ne 'unknown') {
        throw 'ASSERT: large generic CSV must remain unknown.'
    }
    if ($global:BackEndReportLongCsvConversionAttempted) {
        throw 'ASSERT: schema detection must inspect only a bounded header sample, not convert the entire generic CSV.'
    }
    foreach ($name in @('ordered.csv','rss-spelling.csv')) {
        $item = @($data.inventory | Where-Object relative_path -eq $name)
        if ($item.Count -ne 1 -or $item[0].category -ne 'server-memory') {
            throw "ASSERT: '$name' must be recognized by required column names independent of order."
        }
    }
    $ordered = @($data.records | Where-Object { $_.kind -eq 'server-memory' -and $_.values.server_id -eq 'S1' })
    $rss = @($data.records | Where-Object { $_.kind -eq 'server-memory' -and $_.values.server_id -eq 'S2' })
    if ($ordered.Count -ne 1 -or $ordered[0].values.rss_mb -ne 128) {
        throw 'ASSERT: rss_mb input must remain expressed in MB.'
    }
    if ($rss.Count -ne 1 -or $rss[0].values.rss_mb -ne 256) {
        throw 'ASSERT: accepted rss input is defined as MB and must normalize to rss_mb.'
    }
    'PASS: server-memory schema detection is bounded, rejects false positives, and normalizes rss as MB'
}
finally {
    Remove-Item -LiteralPath Function:\global:ConvertFrom-Csv -Force -ErrorAction SilentlyContinue
    if ($priorConvertFunction) { Set-Item -LiteralPath Function:\global:ConvertFrom-Csv -Value $priorConvertFunction.ScriptBlock }
    Remove-Variable -Name BackEndReportLongCsvConversionAttempted -Scope Global -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
}
