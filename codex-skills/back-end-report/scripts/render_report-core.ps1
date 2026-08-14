param([Parameter(Mandatory=$true)][string]$DataPath,[string]$OutputPath,[string]$TemplatePath,[switch]$ValidateOnly)
$ErrorActionPreference='Stop'
$data=Get-Content -Raw -LiteralPath $DataPath|ConvertFrom-Json
foreach($row in @($data.report.server_comparison)){$row|Add-Member -Force priority ([string]$row.assessment.severity);$row|Add-Member -Force likely_cause ([string]$row.assessment.likely_cause);$row|Add-Member -Force recommended_route ([string]$row.assessment.route)}
foreach($row in @($data.report.smaps_end)){$row|Add-Member -Force interpretation ((@($row.assessment.evidence)-join'; ')+' | '+[string]$row.assessment.likely_cause)}
$data.schema_version='1.0'
$compat=Join-Path ([IO.Path]::GetTempPath()) ("back-end-report-{0}.json" -f [guid]::NewGuid())
try{
 $data|ConvertTo-Json -Depth 20|Set-Content -LiteralPath $compat -Encoding UTF8
 $legacy=Join-Path $PSScriptRoot 'render_report-core-v1.ps1'
 $args=@{DataPath=$compat}
 if($TemplatePath){$args.TemplatePath=$TemplatePath}
 if($OutputPath){$args.OutputPath=$OutputPath}
 if($ValidateOnly){$args.ValidateOnly=$true}
 & $legacy @args
}finally{
 if(Test-Path -LiteralPath $compat){Remove-Item -LiteralPath $compat -Force}
}
