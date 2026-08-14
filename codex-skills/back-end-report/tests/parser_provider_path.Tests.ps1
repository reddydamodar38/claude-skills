$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$scratch = Join-Path $env:TEMP ('back-end-provider-path-' + [guid]::NewGuid().ToString('N'))
$driveName = 'BER' + [guid]::NewGuid().ToString('N').Substring(0, 5)

try {
    New-Item -ItemType Directory -Path $scratch | Out-Null
    $fixtureRoot = Join-Path $PSScriptRoot 'fixtures\baseline'
    New-PSDrive -Name $driveName -PSProvider FileSystem -Root $fixtureRoot | Out-Null

    $parsed = Join-Path $scratch 'parsed.json'
    & "$root\scripts\parse_artifacts.ps1" -RunPath "${driveName}:\" -RunName baseline -OutputPath $parsed
    $data = Get-Content -LiteralPath $parsed -Raw | ConvertFrom-Json

    $expected = 'NODE1\meminfo.txt'
    $actual = @($data.inventory | Where-Object relative_path -eq $expected)
    if ($actual.Count -ne 1) {
        throw "ASSERT: provider-qualified roots must produce provider-relative paths; expected '$expected'."
    }
    'PASS: provider-qualified run roots use filesystem provider paths'
}
finally {
    Remove-PSDrive -Name $driveName -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
}
