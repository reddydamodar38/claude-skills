$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$scratch = Join-Path $env:TEMP ('back-end-noise-content-' + [guid]::NewGuid().ToString('N'))

try {
    $run = Join-Path $scratch 'run'
    New-Item -ItemType Directory -Path $run -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $run 'index.html') -Value 'server_id,pid,rss_mb`nS1,1,100'
    Set-Content -LiteralPath (Join-Path $run 'awr_report.html') -Value '<html>AWR report</html>'

    $parsed = Join-Path $scratch 'parsed.json'
    & "$root\scripts\parse_artifacts.ps1" -RunPath $run -RunName baseline -OutputPath $parsed
    $data = Get-Content -LiteralPath $parsed -Raw | ConvertFrom-Json
    $index = @($data.inventory | Where-Object relative_path -eq 'index.html')
    $awr = @($data.inventory | Where-Object relative_path -eq 'awr_report.html')
    if ($index.Count -ne 1 -or $index[0].category -ne 'unknown') {
        throw 'ASSERT: generic HTML assets must be hashed but not content-classified.'
    }
    if ($index[0].sha256 -notmatch '^[0-9a-f]{64}$') {
        throw 'ASSERT: skipped generic HTML assets must retain SHA-256 evidence.'
    }
    if ($awr.Count -ne 1 -or $awr[0].category -ne 'awr') {
        throw 'ASSERT: evidence-hinted HTML filenames must remain classified.'
    }
    'PASS: generic report assets skip content while evidence-hinted assets remain classified'
}
finally {
    Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
}
