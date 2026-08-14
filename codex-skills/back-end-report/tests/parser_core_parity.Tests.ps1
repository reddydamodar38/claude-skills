param([switch]$SkipPortabilityCheck)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$corePath = Join-Path $root 'scripts\parser_core.ps1'
$scratch = Join-Path $env:TEMP ('back-end-parser-core-parity-' + [guid]::NewGuid().ToString('N'))

function Assert-True($Value, [string]$Message) {
    if (-not $Value) { throw "ASSERT: $Message" }
}

function Normalize-ParserDocument($Document) {
    if ($Document.PSObject.Properties['path']) {
        $Document.PSObject.Properties.Remove('path')
    }
    if ($Document.PSObject.Properties['diagnostics']) {
        $Document.PSObject.Properties.Remove('diagnostics')
    }
    $Document
}


Assert-True (Test-Path -LiteralPath $corePath -PathType Leaf) 'explicit parser core entry point scripts\parser_core.ps1 is missing'
. $corePath
foreach ($commandName in @('Get-ArtifactContentPolicy', 'Get-ArtifactCategory', 'Invoke-ArtifactParse')) {
    Assert-True ($null -ne (Get-Command $commandName -CommandType Function -ErrorAction SilentlyContinue)) "core function $commandName is missing"
}

try {
    New-Item -ItemType Directory -Path $scratch | Out-Null
    $expected = Normalize-ParserDocument (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'fixtures\parser-core-baseline-expected.json') -Raw | ConvertFrom-Json)
    $normalizedBaseline = Join-Path $scratch 'baseline'
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'fixtures\baseline') -Destination $normalizedBaseline -Recurse
    foreach ($inventoryRow in @($expected.inventory)) {
        $scratchFile = Join-Path $normalizedBaseline ([string]$inventoryRow.relative_path)
        Assert-True (Test-Path -LiteralPath $scratchFile -PathType Leaf) "oracle inventory file is missing from scratch baseline: $($inventoryRow.relative_path)"
        $lastWriteUtc = [datetime]::Parse([string]$inventoryRow.last_write_utc, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind)
        [IO.File]::SetLastWriteTimeUtc($scratchFile, $lastWriteUtc)
    }
    $actualPath = Join-Path $scratch 'actual.json'
    & (Join-Path $root 'scripts\parse_artifacts.ps1') -RunPath $normalizedBaseline -RunName baseline -OutputPath $actualPath

    $actual = Normalize-ParserDocument (Get-Content -LiteralPath $actualPath -Raw | ConvertFrom-Json)
    $expectedJson = $expected | ConvertTo-Json -Depth 12 -Compress
    $actualJson = $actual | ConvertTo-Json -Depth 12 -Compress
    Assert-True ($expectedJson -ceq $actualJson) 'refactored parser output differs from the preserved pre-refactor baseline output'
    if (-not $SkipPortabilityCheck) {
        $portableRoot = Join-Path $scratch 'portable-root'
        New-Item -ItemType Directory -Path (Join-Path $portableRoot 'scripts') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $portableRoot 'tests\fixtures') -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $root 'scripts\parser_core.ps1') -Destination (Join-Path $portableRoot 'scripts\parser_core.ps1')
        Copy-Item -LiteralPath (Join-Path $root 'scripts\parse_artifacts.ps1') -Destination (Join-Path $portableRoot 'scripts\parse_artifacts.ps1')
        Copy-Item -LiteralPath $PSCommandPath -Destination (Join-Path $portableRoot 'tests\parser_core_parity.Tests.ps1')
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'fixtures\baseline') -Destination (Join-Path $portableRoot 'tests\fixtures\baseline') -Recurse
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'fixtures\parser-core-baseline-expected.json') -Destination (Join-Path $portableRoot 'tests\fixtures\parser-core-baseline-expected.json')
        $perturbedUtc = [datetime]'2001-01-01T00:00:00Z'
        foreach ($fixtureFile in @(Get-ChildItem -LiteralPath (Join-Path $portableRoot 'tests\fixtures\baseline') -Recurse -File)) {
            [IO.File]::SetLastWriteTimeUtc($fixtureFile.FullName, $perturbedUtc)
        }
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $portableRoot 'tests\parser_core_parity.Tests.ps1') -SkipPortabilityCheck
        Assert-True ($LASTEXITCODE -eq 0) 'parity test failed when copied to a different root'
    }
    Write-Output 'PASS: parser core entry points and exact baseline parity'
} finally {
    Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
}






