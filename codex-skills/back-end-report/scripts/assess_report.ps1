param(
    [Parameter(Mandatory=$true)][string]$DataPath,
    [Parameter(Mandatory=$true)][string]$OutputPath,
    [string]$ThresholdsPath
)
$ErrorActionPreference='Stop'
if(-not $ThresholdsPath){$ThresholdsPath=Join-Path $PSScriptRoot '..\references\default-thresholds.json'}

function Value($Row,[string]$Name){$p=$Row.PSObject.Properties[$Name];if($p){$p.Value}else{$null}}
function Percent($Baseline,$Current){if($null -eq $Baseline -or $null -eq $Current -or [double]$Baseline -eq 0){return $null};(([double]$Current-[double]$Baseline)/[Math]::Abs([double]$Baseline))*100}
function Severity($Value,$Bands){if($null -eq $Value){return 'None'};$v=[double]$Value;if($v -ge [double]$Bands.high){'High'}elseif($v -ge [double]$Bands.medium){'Medium'}elseif($v -gt 0){'Low'}else{'None'}}
function Confidence($Row){$paths=@(Value $Row 'source_paths');$b=@($paths|Where-Object{$_ -like 'baseline:*'}).Count;$c=@($paths|Where-Object{$_ -like 'current:*'}).Count;$bn=@($Row.PSObject.Properties|Where-Object{$_.Name -match '^baseline(_|$)' -and $null-ne$_.Value -and $_.Value-is[ValueType]}).Count;$cn=@($Row.PSObject.Properties|Where-Object{$_.Name -match '^current(_|$)' -and $null-ne$_.Value -and $_.Value-is[ValueType]}).Count;if($b-and$c-and$bn-and$cn){'High'}elseif(($b-and$bn)-or($c-and$cn)){'Medium'}else{'Low'}}
function Set-Assessment($Row,[string]$Severity,[string[]]$Evidence,[string]$Cause,[string]$Route){
    $a=[ordered]@{severity=$Severity;confidence=(Confidence $Row);evidence=@($Evidence|Where-Object{$_});likely_cause=$Cause;route=$Route}
    if(!$a.evidence.Count){$a.evidence=@('No comparable numeric evidence available')}
    $p=$Row.PSObject.Properties['assessment'];if($p){$p.Value=[pscustomobject]$a}else{$Row|Add-Member -NotePropertyName assessment -NotePropertyValue ([pscustomobject]$a)}
}
try{
    $data=Get-Content -Raw -LiteralPath (Resolve-Path -LiteralPath $DataPath)|ConvertFrom-Json
    $t=Get-Content -Raw -LiteralPath (Resolve-Path -LiteralPath $ThresholdsPath)|ConvertFrom-Json
    foreach($r in @($data.report.server_comparison)){
        $d=Value $r 'delta_avg_rss_mb';$sev=Severity $d $t.memory.rss_delta_mb
        Set-Assessment $r $sev @(('average RSS baseline={0} MB; current={1} MB; delta={2} MB' -f (Value $r 'baseline_avg_rss_mb'),(Value $r 'current_avg_rss_mb'),$d)) $(if($sev -eq 'None'){'Current memory is unchanged, lower, or unavailable; no adverse finding is supported'}else{'Memory increase observed; available evidence does not isolate retained heap from native/off-heap memory'}) 'Application owner: correlate GC and smaps evidence before tuning'
    }
    foreach($r in @($data.report.gc_comparison)){
        $pct=Percent (Value $r 'baseline_final_after_gc_mb') (Value $r 'current_final_after_gc_mb');$sev=Severity $pct $t.gc.after_gc_delta_pct
        Set-Assessment $r $sev @(('final after-GC baseline={0} MB; current={1} MB; delta_pct={2:N1}' -f (Value $r 'baseline_final_after_gc_mb'),(Value $r 'current_final_after_gc_mb'),$pct)) $(if($sev -eq 'None'){'After-GC occupancy is unchanged, lower, or unavailable; no adverse finding is supported'}else{'Higher after-GC occupancy is consistent with retained-heap growth; object-level cause is not established'}) 'JVM/application owner: inspect heap-retention evidence'
    }
    foreach($r in @($data.report.database_summary)){
        $pct=Percent (Value $r 'baseline') (Value $r 'current');$sev=Severity $pct $t.database.delta_pct
        Set-Assessment $r $sev @(('{0} baseline={1}; current={2}; delta={3}; delta_pct={4:N1}' -f (Value $r 'metric'),(Value $r 'baseline'),(Value $r 'current'),(Value $r 'delta'),$pct)) $(if($sev -eq 'None'){'Database metric is unchanged, lower, or unavailable; no adverse finding is supported'}else{'Database metric regression observed; summary data does not establish a causal SQL or configuration change'}) 'Database owner: correlate AWR and SQL evidence'
    }
    foreach($r in @($data.report.sql_comparison)){
        $pct=Value $r 'elapsed_delta_pct';if($null -eq $pct){$pct=Percent (Value $r 'avg_elapsed_baseline_ms') (Value $r 'avg_elapsed_current_ms')}
        if((Value $r 'executions_current') -lt $t.sql.minimum_current_executions){$sev='None'}else{$sev=Severity $pct $t.sql.avg_elapsed_delta_pct}
        $ph=Value $r 'plan_hash';Set-Assessment $r $sev @(('avg elapsed baseline={0} ms; current={1} ms; delta_pct={2}; executions current={3}; plan hash={4}' -f (Value $r 'avg_elapsed_baseline_ms'),(Value $r 'avg_elapsed_current_ms'),$pct,(Value $r 'executions_current'),$ph)) $(if($sev -eq 'None'){"SQL latency is unchanged, lower, or unavailable for plan hash $ph; no adverse finding is supported"}else{"Latency regression observed for plan hash $ph; plan causality is not established without a baseline/current plan comparison"}) 'Database/SQL owner: compare execution plans and workload mix'
    }
    foreach($r in @($data.report.awr_summary)){
        $pct=Percent (Value $r 'baseline') (Value $r 'current');$sev=Severity $pct $t.awr.delta_pct;$q=Value $r 'qualification'
        Set-Assessment $r $sev @(('{0} baseline={1}; current={2}; delta_pct={3:N1}; qualification={4}' -f (Value $r 'metric_wait_event'),(Value $r 'baseline'),(Value $r 'current'),$pct,$q)) $(if($sev -eq 'None'){'AWR metric is unchanged, lower, or unavailable; no adverse finding is supported'}else{'AWR metric regression observed; cause is not established and comparability is limited by the stated period/workload qualification'}) 'Database owner: review qualified AWR sections and workload context'
    }
    foreach($r in @($data.report.smaps_end)){$d=Value $r 'delta_pss_mb';$sev=Severity $d $t.memory.rss_delta_mb;Set-Assessment $r $sev @(('PSS baseline={0} MB; current={1} MB; delta={2} MB; private dirty delta={3} MB' -f (Value $r 'baseline_pss_mb'),(Value $r 'current_pss_mb'),$d,(Value $r 'delta_private_dirty_mb'))) $(if($sev -eq 'None'){'PSS is unchanged, lower, or unavailable; no adverse finding is supported'}else{'PSS growth with private-dirty evidence is consistent with native/off-heap growth; allocation cause is not established'}) 'Application owner: correlate smaps categories with heap evidence'}
    foreach($r in @($data.report.instance_summary)){$pairs=@(@('baseline_configured_instances','current_configured_instances'),@('baseline_xms_mb','current_xms_mb'),@('baseline_xmx_mb','current_xmx_mb'));$changed=$false;foreach($pair in $pairs){$bv=Value $r $pair[0];$cv=Value $r $pair[1];if($null-ne$bv-and$null-ne$cv-and$bv-ne$cv){$changed=$true}};$sev=if($changed){'Medium'}else{'None'};Set-Assessment $r $sev @(('instances baseline={0}; current={1}; Xms baseline={2}; current={3}; Xmx baseline={4}; current={5}' -f (Value $r 'baseline_configured_instances'),(Value $r 'current_configured_instances'),(Value $r 'baseline_xms_mb'),(Value $r 'current_xms_mb'),(Value $r 'baseline_xmx_mb'),(Value $r 'current_xmx_mb'))) $(if($changed){'A comparable JVM or instance configuration change is observed; performance impact is not established'}else{'No comparable JVM or instance configuration change is supported by both runs'}) 'Application/platform owner: correlate configuration changes with metric timing'}
    foreach($r in @($data.report.ndump_summary)){$d=Value $r 'delta_count';Set-Assessment $r (Severity $d $t.ndump.delta_count) @(('dump count baseline={0}; current={1}; delta={2}; delta_mb={3}' -f (Value $r 'baseline_file_count'),(Value $r 'current_file_count'),$d,(Value $r 'delta_mb'))) $(if((Severity $d $t.ndump.delta_count) -eq 'None'){'Diagnostic dump count is unchanged, lower, or unavailable; no adverse finding is supported'}else{'New diagnostic dumps indicate a current-run failure artifact; the dump signature is required to identify cause'}) 'Application/platform owner: triage signatures and timestamps'}
    foreach($r in @($data.report.cmb_summary)){$d=([double](Value $r 'current_warnings_errors')-[double](Value $r 'baseline_warnings_errors'));Set-Assessment $r (Severity $d $t.cmb.new_warnings_errors) @(('warnings/errors baseline={0}; current={1}; new={2}; key difference={3}' -f (Value $r 'baseline_warnings_errors'),(Value $r 'current_warnings_errors'),$d,(Value $r 'key_difference'))) $(if((Severity $d $t.cmb.new_warnings_errors) -eq 'None'){'CMB warning/error count is unchanged, lower, or unavailable; no adverse finding is supported'}else{'New CMB warning/error signatures are present; message text is needed for a narrower cause'}) 'Owning service team: inspect new signatures in CMB source'}
    $all=@();foreach($n in @('server_comparison','gc_comparison','smaps_end','database_summary','sql_comparison','awr_summary','instance_summary','ndump_summary','cmb_summary')){$all+=@($data.report.$n|Where-Object{$_.assessment})}
    $rank=@{None=0;Low=1;Medium=2;High=3};$max=0;foreach($x in $all){$v=$rank[[string]$x.assessment.severity];if($v -gt $max){$max=$v}};$status=@('None','Low','Medium','High')[$max]
    $data.report.details=@($data.report.server_comparison|Where-Object{$_.assessment.severity-eq'High'}|Group-Object server_id|ForEach-Object{$group=@($_.Group);[pscustomobject][ordered]@{server_id=[string]$_.Name;server_name=[string]$_.Name;investigation_route=[string]$group[0].assessment.route;command='Review source_paths and correlate GC/smaps evidence';source_paths=@($group.source_paths|ForEach-Object{$_}|Sort-Object -Unique);nodes=@($group|ForEach-Object{[pscustomobject][ordered]@{node=$_.node;instances=$null;xms_mb_per_jvm=$null;xmx_mb_per_jvm=$null;avg_rss_delta_mb=$_.delta_avg_rss_mb;end_pss_delta_mb=$null;after_gc_delta_mb=$null;assessment=$_.assessment}});series=@()}})
    $baselineErrors=@($data.report.errors_warnings|Where-Object{$_.run-eq'baseline'}|ForEach-Object{[string]$_.signature_message});$planChanges=@($data.report.sql_comparison|Group-Object database,sql_id|Where-Object{@($_.Group|Where-Object{$null-ne$_.executions_baseline}).Count-ne@($_.Group|Where-Object{$null-ne$_.executions_current}).Count-or(@($_.Group|Where-Object{$null-ne$_.executions_baseline}|ForEach-Object plan_hash|Sort-Object)-join',')-ne(@($_.Group|Where-Object{$null-ne$_.executions_current}|ForEach-Object plan_hash|Sort-Object)-join',')}|ForEach-Object{$_.Name});$exec=[pscustomobject][ordered]@{overall_status=$status;top_regressions=@($all|Where-Object{$_.assessment.severity-in@('High','Medium')}|ForEach-Object{$_.assessment.evidence-join'; '});improvements=@($all|Where-Object{$_.assessment.severity-eq'None'-and$_.assessment.likely_cause-match'lower'}|ForEach-Object{$_.assessment.evidence-join'; '});plan_changes=$planChanges;new_errors=@($data.report.errors_warnings|Where-Object{$_.run-eq'current'-and$baselineErrors-notcontains[string]$_.signature_message}|ForEach-Object{[string]$_.signature_message});config_correlations=@();limitations_routes=@($data.report.limitations|ForEach-Object{[string]$_})}
    $ep=$data.report.PSObject.Properties['executive_summary'];if($ep){$ep.Value=$exec}else{$data.report|Add-Member -NotePropertyName executive_summary -NotePropertyValue $exec}
    $parent=Split-Path -Parent $OutputPath;if($parent){New-Item -ItemType Directory -Path $parent -Force|Out-Null}
    $data|ConvertTo-Json -Depth 30|Set-Content -LiteralPath $OutputPath -Encoding UTF8
    Write-Output "PASS: assessments written to $OutputPath";exit 0
}catch{Write-Error $_;exit 1}



