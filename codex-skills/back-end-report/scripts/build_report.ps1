param(
    [Parameter(Mandatory=$true)][string]$BaselinePath,
    [Parameter(Mandatory=$true)][string]$CurrentPath,
    [Parameter(Mandatory=$true)][string]$OutputDirectory,
    [string]$TemplatePath,
    [string]$ThresholdsPath,
    [switch]$InventoryOnly,
    [switch]$JsonOnly,
    [switch]$ValidateOnly
)
$ErrorActionPreference='Stop'
function Invoke-Stage([string]$ScriptPath,[string[]]$Arguments){
    & powershell.exe @('-NoProfile','-ExecutionPolicy','Bypass','-File',$ScriptPath) @Arguments
    if($LASTEXITCODE-ne0){throw "Stage failed ($LASTEXITCODE): $ScriptPath"}
}
$baselineRoot=(Resolve-Path -LiteralPath $BaselinePath).Path
$currentRoot=(Resolve-Path -LiteralPath $CurrentPath).Path
New-Item -ItemType Directory -Path $OutputDirectory -Force|Out-Null
$outputRoot=(Resolve-Path -LiteralPath $OutputDirectory).Path
$scratch=Join-Path ([IO.Path]::GetTempPath()) ('back-end-report-'+[guid]::NewGuid())
New-Item -ItemType Directory -Path $scratch -Force|Out-Null
try{
    $baselineData=Join-Path $scratch 'baseline.json';$currentData=Join-Path $scratch 'current.json'
    Invoke-Stage (Join-Path $PSScriptRoot 'parse_artifacts.ps1') @('-RunPath',$baselineRoot,'-RunName','baseline','-OutputPath',$baselineData)
    Invoke-Stage (Join-Path $PSScriptRoot 'parse_artifacts.ps1') @('-RunPath',$currentRoot,'-RunName','current','-OutputPath',$currentData)
    if($InventoryOnly){Copy-Item $baselineData (Join-Path $outputRoot 'baseline-inventory.json') -Force;Copy-Item $currentData (Join-Path $outputRoot 'current-inventory.json') -Force;Write-Output "PASS: inventory written to $outputRoot";exit 0}
    $rawData=Join-Path $scratch 'report-raw.json';$assessedData=Join-Path $scratch 'report-assessed.json';$finalData=Join-Path $outputRoot 'back-end-report.json'
    Invoke-Stage (Join-Path $PSScriptRoot 'build_report_data.ps1') @('-BaselineDataPath',$baselineData,'-CurrentDataPath',$currentData,'-OutputPath',$rawData)
    $effectiveThresholds=if($ThresholdsPath){(Resolve-Path -LiteralPath $ThresholdsPath).Path}else{(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\references\default-thresholds.json')).Path}
    Invoke-Stage (Join-Path $PSScriptRoot 'assess_report.ps1') @('-DataPath',$rawData,'-OutputPath',$assessedData,'-ThresholdsPath',$effectiveThresholds)
    Invoke-Stage (Join-Path $PSScriptRoot 'validate_report_data.ps1') @('-DataPath',$assessedData,'-ThresholdsPath',$effectiveThresholds)
    Copy-Item -LiteralPath $assessedData -Destination $finalData -Force
    if(-not$JsonOnly-and-not$ValidateOnly){$workbook=Join-Path $outputRoot 'back-end-report.xlsx';$args=@('-DataPath',$finalData,'-OutputPath',$workbook);if($TemplatePath){$args+=@('-TemplatePath',(Resolve-Path -LiteralPath $TemplatePath).Path)};Invoke-Stage (Join-Path $PSScriptRoot 'render_report.ps1') $args}
    Write-Output "PASS: canonical report written to $finalData"
}finally{if(Test-Path $scratch){Remove-Item $scratch -Recurse -Force}}
