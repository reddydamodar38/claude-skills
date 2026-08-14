param([Parameter(Mandatory=$true)][string]$DataPath,[string]$OutputPath,[string]$TemplatePath,[switch]$ValidateOnly)
$ErrorActionPreference='Stop'
if(!$TemplatePath){$TemplatePath=Join-Path $PSScriptRoot '..\assets\reference-workbook.xlsx'}
$data=Get-Content -Raw -LiteralPath $DataPath|ConvertFrom-Json
foreach($name in @('database_summary','sql_comparison','awr_summary','instance_summary','ndump_summary','cmb_summary','artifact_coverage','errors_warnings')){if($null -eq $data.report.$name){throw "report.$name is required"}}
$core=Join-Path $PSScriptRoot 'render_report-core.ps1'
if($ValidateOnly){& $core -DataPath $DataPath -TemplatePath $TemplatePath -ValidateOnly;return}
if(!$OutputPath){throw 'OutputPath is required unless ValidateOnly is used.'}
if($null -eq [type]::GetTypeFromProgID('Excel.Application')){
    throw 'Microsoft Excel automation is unavailable. JSON validation remains available with -ValidateOnly; workbook OPC validation remains available through validate_workbook.ps1.'
}
& $core -DataPath $DataPath -OutputPath $OutputPath -TemplatePath $TemplatePath
& (Join-Path $PSScriptRoot 'add_extended_sheets.ps1') -DataPath $DataPath -WorkbookPath $OutputPath
$extendedRows=0;foreach($name in @('database_summary','sql_comparison','awr_summary','instance_summary','ndump_summary','cmb_summary','artifact_coverage','errors_warnings')){$extendedRows+=@($data.report.$name).Count}
$minimumCharts=if($extendedRows -gt 0){1}else{0}
& (Join-Path $PSScriptRoot 'validate_workbook.ps1') -Path $OutputPath -RequireExtended -MinimumCharts $minimumCharts

