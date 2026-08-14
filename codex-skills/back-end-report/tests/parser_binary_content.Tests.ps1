$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$scratch = Join-Path $env:TEMP ('back-end-binary-content-' + [guid]::NewGuid().ToString('N'))

try {
    $run = Join-Path $scratch 'run'
    New-Item -ItemType Directory -Path $run -Force | Out-Null
    $binaryNames = @('screenshot.png','report.pdf','legacy.doc','document.docx','legacy.xls','workbook.xlsx','font.woff2','image.iso')
    foreach ($name in $binaryNames) {
        [IO.File]::WriteAllBytes(
            (Join-Path $run $name),
            [Text.Encoding]::UTF8.GetBytes("server_id,pid,rss_mb`nS1,1,100")
        )
    }
    Set-Content -LiteralPath (Join-Path $run 'meminfo') -Value "MemTotal: 2048 kB`nMemAvailable: 1024 kB"
    Set-Content -LiteralPath (Join-Path $run 'gc_SCP1.log') -Value '100M->50M 0.1 secs'
    Set-Content -LiteralPath (Join-Path $run 'awr_report.html') -Value '<html>AWR report</html>'

    $parsed = Join-Path $scratch 'parsed.json'
    & "$root\scripts\parse_artifacts.ps1" -RunPath $run -RunName baseline -OutputPath $parsed
    $data = Get-Content -LiteralPath $parsed -Raw | ConvertFrom-Json
    foreach ($name in $binaryNames) {
        $item = @($data.inventory | Where-Object relative_path -eq $name)
        if ($item.Count -ne 1) { throw "ASSERT: binary artifact '$name' must remain inventoried and hashed." }
        if ($item[0].category -ne 'unknown') {
            throw "ASSERT: binary/unrecognized content '$name' must not be decoded for classification, actual=$($item[0].category)."
        }
        if ($item[0].sha256 -notmatch '^[0-9a-f]{64}$') {
            throw "ASSERT: binary artifact '$name' must retain SHA-256 evidence."
        }
    }
    $expected = @{meminfo='node-memory';'gc_SCP1.log'='gc';'awr_report.html'='awr'}
    foreach ($name in $expected.Keys) {
        $item = @($data.inventory | Where-Object relative_path -eq $name)
        if ($item.Count -ne 1 -or $item[0].category -ne $expected[$name]) {
            throw "ASSERT: supported text evidence '$name' must remain readable as $($expected[$name])."
        }
    }
    'PASS: binary content is skipped while supported text evidence remains readable'
}
finally {
    Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
}
