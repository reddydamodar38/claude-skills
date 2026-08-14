param()
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$renderer=Join-Path $root 'scripts\add_extended_sheets.ps1'
$helpers=Join-Path $root 'scripts\workbook_helpers.ps1'
function Assert($condition,[string]$message){if(!$condition){throw "ASSERT: $message"}}

. $helpers

$assessment=[pscustomobject]@{severity='High';confidence='Medium';evidence=@('delta=42 MB','same server S397');likely_cause='Retained heap is higher';route='JVM owner: inspect heap'}
$formatted=Format-Assessment $assessment
Assert ($formatted -match 'Severity: High') 'structured severity was not rendered'
Assert ($formatted -match 'Confidence: Medium') 'structured confidence was not rendered'
Assert ($formatted -match 'Evidence: delta=42 MB; same server S397') 'assessment evidence was not rendered'
Assert ($formatted -match 'Cause: Retained heap is higher') 'likely cause was not rendered'
Assert ($formatted -match 'Route: JVM owner: inspect heap') 'route was not rendered'
Assert ($formatted -notmatch 'System\.Management|PSCustomObject') 'assessment rendered as an object dump'

$temp=Join-Path ([IO.Path]::GetTempPath()) ("workbook-behavior-{0}" -f [guid]::NewGuid())
$baseline=Join-Path $temp 'baseline';$current=Join-Path $temp 'current';New-Item -ItemType Directory -Path $baseline,$current|Out-Null
Set-Content -LiteralPath (Join-Path $baseline 'b.log') -Value 'b';Set-Content -LiteralPath (Join-Path $current 'c.log') -Value 'c'
try{
    Assert ((Resolve-ProvenancePath 'baseline:b.log' $baseline $current) -eq (Join-Path $baseline 'b.log')) 'baseline provenance did not resolve against baseline root'
    Assert ((Resolve-ProvenancePath 'current:c.log' $baseline $current) -eq (Join-Path $current 'c.log')) 'current provenance did not resolve against current root'
    Assert ($null -eq (Resolve-ProvenancePath 'current:missing.log' $baseline $current)) 'missing provenance path should not resolve'
}finally{Remove-Item -LiteralPath $temp -Recurse -Force}

$sqlChanged=[pscustomobject]@{baseline_plan_hashes=@('10','11');current_plan_hashes=@('11','12')}
$sqlSame=[pscustomobject]@{baseline_plan_hashes=@('10','11');current_plan_hashes=@('11','10')}
Assert (Test-PlanChange $sqlChanged) 'baseline/current plan hash sets should detect a change'
Assert (!(Test-PlanChange $sqlSame)) 'equivalent plan hash sets should not detect a change'

$finding=[pscustomobject]@{node='APP01';server_id='397';assessment=$assessment}
$stableConfig=[pscustomobject]@{node='APP01';server_id='397';property='Xmx';baseline='1g';current='2g'}
$nodeOnly=[pscustomobject]@{node='APP01';property='Xmx';baseline='1g';current='2g'}
$otherConfig=[pscustomobject]@{node='APP02';server_id='397';property='Xmx';baseline='1g';current='2g'}
Assert (Test-CorrelatedConfig $stableConfig @($finding)) 'stable node/server evidence should permit correlation'
Assert (!(Test-CorrelatedConfig $nodeOnly @($finding))) 'node-only evidence should not be labeled correlated'
Assert (!(Test-CorrelatedConfig $otherConfig @($finding))) 'mismatched node/server should not be labeled correlated'

Assert ((Get-Severity $assessment) -eq 'High') 'severity helper ignored structured assessment'
Assert ((Get-DeltaDisposition 'elapsed_delta_pct' 10 $assessment) -eq 'Regression') 'positive latency delta should be a regression'
Assert ((Get-DeltaDisposition 'delta_memavailable_mb' 10 $assessment) -eq 'Improvement') 'positive available-memory delta should be an improvement'

$dummy=Join-Path ([IO.Path]::GetTempPath()) ("workbook-no-com-{0}.json" -f [guid]::NewGuid())
@{report=@{database_summary=@();sql_comparison=@();awr_summary=@();instance_summary=@();ndump_summary=@();cmb_summary=@();artifact_coverage=@();errors_warnings=@()}}|ConvertTo-Json -Depth 5|Set-Content -LiteralPath $dummy
try{
    if($null -eq [type]::GetTypeFromProgID('Excel.Application')){
        $skip=& $renderer -DataPath $dummy -WorkbookPath (Join-Path $env:TEMP 'none.xlsx') 2>&1|Out-String
        Assert ($skip -match '^SKIP: Excel COM') 'actual extended renderer call did not explicitly skip without COM'
        $render=Join-Path $root 'scripts\render_report.ps1';$failed=$false
        try{& $render -DataPath $dummy -OutputPath (Join-Path $env:TEMP 'none.xlsx') 2>&1|Out-Null}catch{$failed=$_.Exception.Message -match 'Excel automation is unavailable'}
        Assert $failed 'normal workbook rendering did not fail clearly without COM'
    }
}finally{Remove-Item -LiteralPath $dummy -Force -ErrorAction SilentlyContinue}

Write-Output 'PASS: workbook behavior tests'

