$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$scratch = Join-Path $env:TEMP ('back-end-zip-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $scratch | Out-Null
function Assert-True($Value, [string]$Message) { if (-not $Value) { throw "ASSERT: $Message" } }
try {
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zipPath = Join-Path $scratch 'unsafe.zip'
    $stream = [IO.File]::Open($zipPath, [IO.FileMode]::Create)
    $zip = New-Object IO.Compression.ZipArchive($stream, [IO.Compression.ZipArchiveMode]::Create)
    [void]$zip.CreateEntry('../escape.txt')
    [void]$zip.CreateEntry('safe/gc.log')
    $zip.Dispose(); $stream.Dispose()
    Copy-Item $zipPath (Join-Path $scratch 'duplicate.zip')

    $out = Join-Path $scratch 'parsed.json'
    & (Join-Path $root 'scripts\parse_artifacts.ps1') -RunPath $scratch -RunName baseline -OutputPath $out
    $data = Get-Content -Raw -LiteralPath $out | ConvertFrom-Json
    Assert-True (@($data.inventory | Where-Object is_duplicate).Count -eq 1) 'duplicate hash detected'
    Assert-True (@($data.errors | Where-Object signature_message -match 'traversal').Count -ge 1) 'ZIP traversal entry rejected and reported'
    Assert-True (@($data.zip_entries | Where-Object entry_path -eq 'safe/gc.log').Count -eq 2) 'safe ZIP entries inspected'
    Assert-True (-not (Test-Path (Join-Path $scratch 'escape.txt'))) 'ZIP entries are never extracted'
    Write-Output 'PASS: ZIP safety and duplicate detection'
} finally { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue }


