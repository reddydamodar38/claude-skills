$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$validator=Join-Path $root 'scripts\validate_report_data.ps1';$assessor=Join-Path $root 'scripts\assess_report.ps1';$defaults=Join-Path $root 'references\default-thresholds.json'
$temp=Join-Path $env:TEMP ('validation-edge-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory $temp|Out-Null
function Assert($v,[string]$m){if(!$v){throw "ASSERT: $m"}}
function Report { $h=[ordered]@{};foreach($n in @('limitations','node_summary','server_comparison','gc_comparison','smaps_end','config_changes','database_summary','sql_comparison','awr_summary','instance_summary','ndump_summary','cmb_summary','artifact_coverage','errors_warnings','details')){$h[$n]=@()};$h.executive_summary=[ordered]@{overall_status='None';top_regressions=@();improvements=@();plan_changes=@();new_errors=@();config_correlations=@();limitations_routes=@()};$h }
function Doc { [ordered]@{schema_version='2.0';generated_utc='2026-07-02T12:00:00Z';runs=[ordered]@{baseline=[ordered]@{path='B';nodes=@([ordered]@{name='N1';files=@([ordered]@{relative_path='x';category='smaps';length=1;last_write_utc='2026-07-01T00:00:00Z'})})};current=[ordered]@{path='C';nodes=@()}};report=(Report)} }
function Save($d,[string]$n){$p=Join-Path $temp $n;$d|ConvertTo-Json -Depth 30|Set-Content $p -Encoding UTF8;$p}
function Validate($p,$threshold=$null){$args=@('-NoProfile','-ExecutionPolicy','Bypass','-File',$validator,'-DataPath',$p);if($threshold){$args+=@('-ThresholdsPath',$threshold)};$o=& powershell.exe @args 2>&1|Out-String;[pscustomobject]@{code=$LASTEXITCODE;text=$o}}
try{
 $d=Doc
 $d.report.smaps_end=@([ordered]@{node='N1';server_id='397';baseline_pss_mb=100;current_pss_mb=130;delta_pss_mb=30;baseline_private_dirty_mb=50;current_private_dirty_mb=70;delta_private_dirty_mb=20;source_paths=@('baseline:N1/smaps','current:N1/smaps')})
 $d.report.instance_summary=@([ordered]@{node='N1';server_instance_id='397';name='SCP397';baseline_configured_instances=2;current_configured_instances=3;delta_instances=1;baseline_xms_mb=100;current_xms_mb=100;baseline_xmx_mb=500;current_xmx_mb=500;source_paths=@('baseline:N1/config','current:N1/config')})
 $in=Save $d 'assess.json';$out=Join-Path $temp 'assessed.json';& $assessor -DataPath $in -OutputPath $out -ThresholdsPath $defaults|Out-Null
 $a=Get-Content -Raw $out|ConvertFrom-Json;Assert ($a.report.smaps_end[0].assessment.evidence.Count -gt 0) 'smaps not assessed';Assert ($a.report.instance_summary[0].assessment.evidence.Count -gt 0) 'instance not assessed'
 Assert ($a.report.executive_summary.overall_status -is [string]) 'executive summary overall_status missing'
 foreach($n in @('top_regressions','improvements','plan_changes','new_errors','config_correlations','limitations_routes')){Assert ($a.report.executive_summary.$n -is [array]) ('executive summary '+$n+' must be an array')}
 $subout=Join-Path $temp 'subprocess.json';& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $assessor -DataPath $in -OutputPath $subout | Out-Null;Assert ($LASTEXITCODE -eq 0 -and (Test-Path $subout)) 'default thresholds fail in fresh powershell.exe process'
 $vr=Validate $out;Assert ($vr.code -eq 0) "assessed v2 contract rejected: $($vr.text)"

 $d=Doc;$d.report.server_comparison=@([ordered]@{node='N1';server_id='397';baseline_avg_rss_mb=200;current_avg_rss_mb=100;delta_avg_rss_mb=-100;source_paths=@('baseline:x','current:x')});$in=Save $d 'negative.json';&$assessor -DataPath $in -OutputPath $out -ThresholdsPath $defaults|Out-Null;$a=Get-Content -Raw $out|ConvertFrom-Json
 Assert ($a.report.server_comparison[0].assessment.severity -eq 'None') 'negative memory delta severity';Assert ($a.report.server_comparison[0].assessment.likely_cause -notmatch 'increase|regression') 'negative delta claims increase/regression'
 $d=Doc;$d.report.server_comparison=@([ordered]@{node='N1';server_id='397';baseline_avg_rss_mb=$null;current_avg_rss_mb=$null;delta_avg_rss_mb=$null;source_paths=@('baseline:x','current:x')});$in=Save $d 'no-evidence.json';&$assessor -DataPath $in -OutputPath $out -ThresholdsPath $defaults|Out-Null;$a=Get-Content -Raw $out|ConvertFrom-Json;Assert ($a.report.server_comparison[0].assessment.confidence -ne 'High') 'paths alone produced High confidence'

 $d=Doc;$d.report.database_summary=@([ordered]@{database='D';instance='1';node='DB';metric='DB CPU';baseline=0;current=1;delta=1;unit='s';source_paths=@('current:x');assessment=[ordered]@{severity='Low';confidence='Low';evidence=@('x');likely_cause='x';route='x'}});$vr=Validate (Save $d 'bare-zero.json');Assert ($vr.code -ne 0 -and $vr.text -match 'missing data.*zero') 'bare baseline/current missing-zero guard absent'

 $d=Doc;$d.runs.baseline.nodes[0].name=7;$vr=Validate (Save $d 'bad-node.json');Assert ($vr.code -ne 0 -and $vr.text -match 'name.*string') 'node name type not enforced'
 $d=Doc;$d.runs.baseline.nodes[0].files[0].length=-1;$d.runs.baseline.nodes[0].files[0].last_write_utc='not-a-time';$vr=Validate (Save $d 'bad-file.json');Assert ($vr.code -ne 0 -and $vr.text -match 'length.*nonnegative integer' -and $vr.text -match 'last_write_utc.*ISO') 'file length/time types not enforced'

 $d=Doc;$row=[ordered]@{node='N1';baseline_used_mb=1;current_used_mb=2;delta_used_mb=1;source_paths=@('baseline:x','current:x')};$d.report.node_summary=@($row,$row);$vr=Validate (Save $d 'duplicate-node.json');Assert ($vr.code -ne 0 -and $vr.text -match 'duplicate stable key') 'node_summary stable key uniqueness absent'
 $d=Doc;$d.report.node_summary=@([ordered]@{node='N1';baseline_used_mb=1;current_used_mb=2;delta_used_mb=1;source_paths=@()});$vr=Validate (Save $d 'no-provenance.json');Assert ($vr.code -ne 0 -and $vr.text -match 'source_paths') 'structured-row provenance absent'

 foreach($case in @(@('config_changes',[ordered]@{node='N1';server_id='397';property='jvmargs';source_paths=@('baseline:x','current:x')}),@('artifact_coverage',[ordered]@{run='baseline';node='N1';category='gc';source_paths=@('baseline:x')}),@('errors_warnings',[ordered]@{run='current';node='N1';category='gc';server_database='397';timestamp='2026-07-02T00:00:00Z';signature_message='error';source_paths=@('current:x')}),@('details',[ordered]@{server_id='397';source_paths=@('baseline:x','current:x')}))){$d=Doc;$d.report.($case[0])=@($case[1],$case[1]);$vr=Validate (Save $d ('duplicate-'+$case[0]+'.json'));Assert ($vr.code -ne 0 -and $vr.text -match 'duplicate stable key') ('stable key uniqueness absent for '+$case[0])}

 $d=Doc;$d.report.awr_summary=@([ordered]@{database='D';instance='1';metric_wait_event='DB CPU';baseline=1;current=2;delta=1;unit='s';baseline_period='1-2';current_period='3-4';baseline_duration_minutes=100;current_duration_minutes=115;baseline_workload=100;current_workload=100;qualification='Comparable';source_paths=@('baseline:x','current:x');assessment=[ordered]@{severity='High';confidence='High';evidence=@('x');likely_cause='x';route='x'}})
 $p=Save $d 'awr.json';$vr=Validate $p;Assert ($vr.code -ne 0 -and $vr.text -match 'qualification') 'default AWR duration threshold ignored'
 $t=Get-Content -Raw $defaults|ConvertFrom-Json;$t.awr.duration_tolerance_pct=20;$tp=Save $t 'thresholds.json';$vr=Validate $p $tp;Assert ($vr.code -eq 0) "custom AWR threshold ignored: $($vr.text)"
 $d.report.awr_summary[0].qualification='';$vr=Validate (Save $d 'blank-qualification.json') $tp;Assert ($vr.code -ne 0 -and $vr.text -match 'qualification.*non-empty') 'blank AWR qualification accepted'
 Write-Output 'PASS: validation edge cases'
}finally{Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue}



