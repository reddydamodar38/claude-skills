$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$scratch = Join-Path $env:TEMP ('back-end-node-provenance-' + [guid]::NewGuid().ToString('N'))

function Save-Run([string]$path,[string]$run,$inventory,$records) {
    [ordered]@{run=$run;path=$path;inventory=@($inventory);records=@($records);zip_entries=@();errors=@()} |
        ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $path
}

try {
    New-Item -ItemType Directory -Path $scratch | Out-Null
    $baseline = Join-Path $scratch 'baseline.json'
    $current = Join-Path $scratch 'current.json'
    $output = Join-Path $scratch 'report.json'
    $bInventory = @(
        [pscustomobject]@{relative_path='NODEA\meminfo.txt';node='NODEA';category='node-memory';length=1;last_write_utc='2026-01-01T00:00:00Z';is_duplicate=$false},
        [pscustomobject]@{relative_path='NODEB\meminfo.txt';node='NODEB';category='node-memory';length=1;last_write_utc='2026-01-01T00:00:00Z';is_duplicate=$false}
    )
    $cInventory = @(
        [pscustomobject]@{relative_path='NODEA\z_memory.txt';node='NODEA';category='unknown';length=1;last_write_utc='2026-01-02T00:00:00Z';is_duplicate=$false},
        [pscustomobject]@{relative_path='NODEA\a_meminfo.txt';node='NODEA';category='unknown';length=1;last_write_utc='2026-01-02T00:00:00Z';is_duplicate=$false},
        [pscustomobject]@{relative_path='NODEA\other.bin';node='NODEA';category='unknown';length=1;last_write_utc='2026-01-02T00:00:00Z';is_duplicate=$false}
    )
    $bRecords = @(
        [pscustomobject]@{kind='node-memory';node='NODEA';key='NODEA';values=[pscustomobject]@{used_mb=100};source='NODEA\meminfo.txt'},
        [pscustomobject]@{kind='node-memory';node='NODEB';key='NODEB';values=[pscustomobject]@{used_mb=200};source='NODEB\meminfo.txt'}
    )
    Save-Run $baseline baseline $bInventory $bRecords
    Save-Run $current current $cInventory @()
    & "$root\scripts\build_report_data.ps1" -BaselineDataPath $baseline -CurrentDataPath $current -OutputPath $output
    $data = Get-Content -LiteralPath $output -Raw | ConvertFrom-Json
    $rows = @($data.report.node_summary)
    if ($rows.Count -ne 1 -or $rows[0].node -ne 'NODEA') {
        throw 'ASSERT: node comparisons must include only nodes present in both run inventories.'
    }
    if (@($rows[0].source_paths | Where-Object { $_ -like 'baseline:*' }).Count -ne 1) {
        throw 'ASSERT: node comparison must retain baseline parsed provenance.'
    }
    if (@($rows[0].source_paths | Where-Object { $_ -eq 'current:NODEA\a_meminfo.txt' }).Count -ne 1) {
        throw 'ASSERT: missing parsed-side metrics must use the lexicographically first preferred same-node provenance.'
    }
    'PASS: node comparisons preserve paired provenance without fabricating missing nodes'
}
finally {
    Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
}
