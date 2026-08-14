param()
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$validator = Join-Path $root 'scripts\validate_workbook.ps1'
$template = Join-Path $root 'assets\reference-workbook.xlsx'

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "ASSERT: $Message" }
}

$base = & $validator -Path $template -MinimumCharts 1 2>&1 | Out-String
Assert-True ($base -match 'PASS:') 'base validation should report PASS'

$extendedFailed = $false
try { & $validator -Path $template -RequireExtended 2>&1 | Out-Null } catch {
    $extendedFailed = $_.Exception.Message -match 'Executive Summary'
}
Assert-True $extendedFailed 'extended validation should require Executive Summary and its exact position'

$bad = Join-Path ([IO.Path]::GetTempPath()) ("bad-workbook-{0}.xlsx" -f [guid]::NewGuid())
Copy-Item -LiteralPath $template -Destination $bad
try {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::Open($bad, [IO.Compression.ZipArchiveMode]::Update)
    try {
        $entry = $zip.GetEntry('xl/worksheets/sheet2.xml')
        $reader = [IO.StreamReader]::new($entry.Open())
        try { $xml = $reader.ReadToEnd() } finally { $reader.Dispose() }
        $entry.Delete()
        $entry = $zip.CreateEntry('xl/worksheets/sheet2.xml')
        $writer = [IO.StreamWriter]::new($entry.Open())
        $mutated = [string]($xml -replace '</sheetData>', '<row r="999"><c r="A999" t="e"><v>#REF!</v></c></row></sheetData>')
        try { $writer.Write($mutated) } finally { $writer.Dispose() }
    } finally { $zip.Dispose() }
    $errorDetected = $false
    try { & $validator -Path $bad 2>&1 | Out-Null } catch { $errorDetected = $_.Exception.Message -match 'formula/error' }
    Assert-True $errorDetected 'OPC validation should reject cells containing spreadsheet errors'
} finally { Remove-Item -LiteralPath $bad -Force -ErrorAction SilentlyContinue }

Write-Output 'PASS: workbook OPC validation tests'





