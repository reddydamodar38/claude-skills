param([Parameter(Mandatory=$true)][string]$BaselinePath,[Parameter(Mandatory=$true)][string]$CurrentPath,[Parameter(Mandatory=$true)][string]$OutputPath)
$ErrorActionPreference='Stop'
$tmp=Join-Path ([IO.Path]::GetTempPath()) ('back-end-extract-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $tmp|Out-Null
try{
 $bp=Join-Path $tmp 'baseline.json';$cp=Join-Path $tmp 'current.json'
 & (Join-Path $PSScriptRoot 'parse_artifacts.ps1') -RunPath $BaselinePath -RunName baseline -OutputPath $bp
 & (Join-Path $PSScriptRoot 'parse_artifacts.ps1') -RunPath $CurrentPath -RunName current -OutputPath $cp
 & (Join-Path $PSScriptRoot 'build_report_data.ps1') -BaselineDataPath $bp -CurrentDataPath $cp -OutputPath $OutputPath
 Write-Output "PASS: parsed report data written to $OutputPath"
}finally{Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue}
