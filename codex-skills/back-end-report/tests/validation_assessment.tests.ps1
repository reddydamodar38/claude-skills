$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$assessor=Join-Path $root 'scripts\assess_report.ps1'
$thresholds=Join-Path $root 'references\default-thresholds.json'
$temp=Join-Path ([IO.Path]::GetTempPath()) ("back-end-assessment-{0}" -f [guid]::NewGuid())
New-Item -ItemType Directory -Path $temp|Out-Null
function Assert-Equal($Expected,$Actual,[string]$Message){if($Expected -ne $Actual){throw "FAIL: $Message (expected=$Expected actual=$Actual)"}}
$arrays=@('limitations','node_summary','server_comparison','gc_comparison','smaps_end','config_changes','database_summary','sql_comparison','awr_summary','instance_summary','ndump_summary','cmb_summary','artifact_coverage','errors_warnings','details')
$report=[ordered]@{};foreach($a in $arrays){$report[$a]=@()}
$report.server_comparison=@([ordered]@{node='APP01';server_id='S1';baseline_avg_rss_mb=100;current_avg_rss_mb=225;delta_avg_rss_mb=125;source_paths=@('baseline:APP01/memory.csv','current:APP01/memory.csv')})
$report.gc_comparison=@([ordered]@{node='APP01';server_id='S1';baseline_final_after_gc_mb=100;current_final_after_gc_mb=160;delta_after_gc_mb=60;source_paths=@('baseline:APP01/gc.log','current:APP01/gc.log')})
$report.database_summary=@([ordered]@{database='DB1';instance='1';node='DB01';metric='DB time';baseline=100;current=135;delta=35;unit='seconds';source_paths=@('baseline:DB01/db.txt','current:DB01/db.txt')})
$report.sql_comparison=@([ordered]@{database='DB1';sql_id='abc';plan_hash='123';module_schema='M';executions_baseline=10;executions_current=10;avg_elapsed_baseline_ms=100;avg_elapsed_current_ms=175;elapsed_delta_pct=75;source_paths=@('baseline:DB01/sql.txt','current:DB01/sql.txt')})
$report.awr_summary=@([ordered]@{database='DB1';instance='1';metric_wait_event='DB CPU';baseline=100;current=140;delta=40;unit='seconds';baseline_period='B1-B2';current_period='C1-C2';baseline_duration_minutes=60;current_duration_minutes=60;baseline_workload=100;current_workload=105;qualification='Comparable within configured tolerances';source_paths=@('baseline:DB01/awr.txt','current:DB01/awr.txt')})
$report.ndump_summary=@([ordered]@{node='APP01';server_instance='S1';baseline_file_count=0;current_file_count=4;delta_count=4;baseline_total_mb=0;current_total_mb=5;delta_mb=5;source_paths=@('baseline:APP01/ndump.index','current:APP01/ndump1')})
$report.cmb_summary=@([ordered]@{node='APP01';server_id='S1';baseline_file_count=1;current_file_count=1;delta_count=0;baseline_total_mb=1;current_total_mb=2;delta_mb=1;baseline_warnings_errors=0;current_warnings_errors=6;key_difference='six new errors';source_paths=@('baseline:APP01/cmb_1.log','current:APP01/cmb_1.log')})
$doc=[ordered]@{schema_version='2.0';generated_utc='2026-07-02T12:00:00Z';runs=[ordered]@{baseline=[ordered]@{path='B';nodes=@()};current=[ordered]@{path='C';nodes=@()}};report=$report}
$input=Join-Path $temp 'input.json';$output=Join-Path $temp 'output.json';$doc|ConvertTo-Json -Depth 20|Set-Content $input -Encoding UTF8
try{
 & $assessor -DataPath $input -OutputPath $output -ThresholdsPath $thresholds | Out-Null
 Assert-Equal 0 $LASTEXITCODE 'assessor failed'
 $actual=Get-Content -Raw $output|ConvertFrom-Json
 Assert-Equal 'High' $actual.report.server_comparison[0].assessment.severity 'memory severity'
 Assert-Equal 'High' $actual.report.gc_comparison[0].assessment.severity 'GC severity'
 Assert-Equal 'High' $actual.report.database_summary[0].assessment.severity 'database severity'
 Assert-Equal 'High' $actual.report.sql_comparison[0].assessment.severity 'SQL severity'
 Assert-Equal 'High' $actual.report.awr_summary[0].assessment.severity 'AWR severity'
 Assert-Equal 'High' $actual.report.ndump_summary[0].assessment.severity 'ndump severity'
 Assert-Equal 'High' $actual.report.cmb_summary[0].assessment.severity 'CMB severity'
 if(@($actual.report.sql_comparison[0].assessment.evidence).Count -lt 1){throw 'FAIL: assessment evidence is empty'}
 if($actual.report.sql_comparison[0].assessment.likely_cause -notmatch 'plan hash|execution|latency'){throw 'FAIL: SQL likely cause is not evidence-bounded'}

 $custom=Get-Content -Raw $thresholds|ConvertFrom-Json;$custom.memory.rss_delta_mb.high=200
 $customPath=Join-Path $temp 'custom.json';$custom|ConvertTo-Json -Depth 10|Set-Content $customPath -Encoding UTF8
 & $assessor -DataPath $input -OutputPath $output -ThresholdsPath $customPath | Out-Null
 $actual=Get-Content -Raw $output|ConvertFrom-Json
 Assert-Equal 'Medium' $actual.report.server_comparison[0].assessment.severity 'custom threshold was ignored'
 Write-Output 'PASS: validation assessment tests'
}finally{Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue}
