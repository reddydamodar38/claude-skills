param([Parameter(Mandatory=$true)][string]$DataPath,[string]$ThresholdsPath)
if(-not $ThresholdsPath){$ThresholdsPath=Join-Path $PSScriptRoot '..\references\default-thresholds.json'}
$ErrorActionPreference='Stop'
$script:Errors=New-Object 'Collections.Generic.List[string]'
function Fail([string]$Message){$script:Errors.Add($Message)}
function Prop($Object,[string]$Name){if($null -eq $Object){return $null};$p=$Object.PSObject.Properties[$Name];if($p){Write-Output -NoEnumerate $p.Value}else{$null}}
function Has($Object,[string]$Name){$null -ne $Object -and $null -ne $Object.PSObject.Properties[$Name]}
function Is-Array($Value){$null -ne $Value -and $Value -is [System.Array]}
function Is-Number($Value){$Value -is [byte] -or $Value -is [int16] -or $Value -is [int32] -or $Value -is [int64] -or $Value -is [single] -or $Value -is [double] -or $Value -is [decimal]}
function Require-Properties($Object,[string[]]$Names,[string]$At){foreach($n in $Names){if(-not (Has $Object $n)){Fail "$At.$n is required"}}}
function Check-Allowed($Object,[string[]]$Names,[string]$At){foreach($p in $Object.PSObject.Properties.Name){if($p -notin $Names){Fail "$At.$p is not allowed by strict schema v2"}}}
function Check-Assessment($Row,[string]$At){
    $a=Prop $Row 'assessment';if($null -eq $a){Fail "$At.assessment is required";return}
    $names=@('severity','confidence','evidence','likely_cause','route');Require-Properties $a $names "$At.assessment";Check-Allowed $a $names "$At.assessment"
    if((Prop $a 'severity') -notin @('None','Low','Medium','High')){Fail "$At.assessment.severity is invalid"}
    if((Prop $a 'confidence') -notin @('Low','Medium','High')){Fail "$At.assessment.confidence is invalid"}
    if(-not (Is-Array (Prop $a 'evidence')) -or (Prop $a 'evidence').Count -eq 0){Fail "$At.assessment.evidence must be a non-empty array"}
    foreach($n in @('likely_cause','route')){if([string]::IsNullOrWhiteSpace([string](Prop $a $n))){Fail "$At.assessment.$n must be non-empty"}}
}
function Check-Sources($Row,[string]$At,[switch]$Paired){
    $s=Prop $Row 'source_paths';if(-not (Is-Array $s) -or @($s).Count -eq 0){Fail "$At.source_paths must be a non-empty array";return}
    foreach($x in @($s)){if($x -notmatch '^(baseline|current):.+'){Fail "$At source provenance '$x' must start with baseline: or current:"}}
    if($Paired){if(-not @($s|Where-Object{$_ -like 'baseline:*'}).Count){Fail "$At missing baseline source provenance"};if(-not @($s|Where-Object{$_ -like 'current:*'}).Count){Fail "$At missing current source provenance"}}
}
function Check-Triplet($Row,[string]$Baseline,[string]$Current,[string]$Delta,[string]$At){
    if(-not (Has $Row $Baseline) -and -not (Has $Row $Current) -and -not (Has $Row $Delta)){return}
    $b=Prop $Row $Baseline;$c=Prop $Row $Current;$d=Prop $Row $Delta
    if($null -eq $b -or $null -eq $c){if($null -ne $d){Fail "$At.$Delta must be null when either comparison value is null"};return}
    if(-not (Is-Number $b) -or -not (Is-Number $c)){Fail "$At $Baseline/$Current must be numbers or null";return}
    if($null -eq $d -or -not (Is-Number $d) -or [Math]::Abs(([double]$c-[double]$b)-[double]$d) -gt .001){Fail "$At.$Delta must equal current minus baseline"}
}
function Check-MissingZero($Row,[string]$At){
    $sources=Prop $Row 'source_paths';$hasB=@($sources|Where-Object{$_ -like 'baseline:*'}).Count -gt 0;$hasC=@($sources|Where-Object{$_ -like 'current:*'}).Count -gt 0
    foreach($p in $Row.PSObject.Properties){if(($p.Name -eq 'baseline' -or $p.Name -like 'baseline_*') -and (Is-Number $p.Value) -and [double]$p.Value -eq 0 -and -not $hasB){Fail "$At missing data must be null, not zero (no baseline provenance for $($p.Name))"};if(($p.Name -eq 'current' -or $p.Name -like 'current_*') -and (Is-Number $p.Value) -and [double]$p.Value -eq 0 -and -not $hasC){Fail "$At missing data must be null, not zero (no current provenance for $($p.Name))"}}
}
function Key-For($Row,[string[]]$Fields){(@($Fields|ForEach-Object{[string](Prop $Row $_)}) -join '|').ToUpperInvariant()}
function Check-Rows($Rows,[string]$Name,[string[]]$Required,[string[]]$Keys,[string[]]$Allowed,[switch]$Assessed,[switch]$Paired,[switch]$Provenanced){
    $seen=@{};$i=0;foreach($r in @($Rows)){$at="report.$Name[$i]";Require-Properties $r $Required $at;if($Allowed.Count){Check-Allowed $r $Allowed $at};if($Keys.Count){$key=Key-For $r $Keys;if($key -match '^\|*$'){Fail "$at stable key is empty"}elseif($seen.ContainsKey($key)){Fail "$at duplicate stable key '$key'"}else{$seen[$key]=$true}};if($Assessed){Check-Assessment $r $at};if($Paired){Check-Sources $r $at -Paired;Check-MissingZero $r $at}elseif($Provenanced){Check-Sources $r $at;Check-MissingZero $r $at};$i++}
}
try{
    $data=Get-Content -Raw -LiteralPath (Resolve-Path -LiteralPath $DataPath)|ConvertFrom-Json
    $thresholds=Get-Content -Raw -LiteralPath (Resolve-Path -LiteralPath $ThresholdsPath)|ConvertFrom-Json
    Require-Properties $data @('schema_version','generated_utc','runs','report') 'root';Check-Allowed $data @('schema_version','generated_utc','runs','report') 'root'
    if((Prop $data 'schema_version') -ne '2.0'){Fail 'schema_version must be 2.0'}
    $stamp=[datetime]::MinValue;if(-not [datetime]::TryParse([string](Prop $data 'generated_utc'),[ref]$stamp)){Fail 'generated_utc must be an ISO date-time'}
    $runs=Prop $data 'runs';Require-Properties $runs @('baseline','current') 'runs';Check-Allowed $runs @('baseline','current') 'runs'
    foreach($runName in @('baseline','current')){$run=Prop $runs $runName;Require-Properties $run @('path','nodes') "runs.$runName";Check-Allowed $run @('path','nodes') "runs.$runName";if(-not (Is-Array (Prop $run 'nodes'))){Fail "runs.$runName.nodes must be an array"}else{foreach($node in (Prop $run 'nodes')){Require-Properties $node @('name','files') "runs.$runName.nodes[]";Check-Allowed $node @('name','files') "runs.$runName.nodes[]";if(-not ((Prop $node 'name') -is [string])){Fail "runs.$runName.nodes[].name must be a string"};if(-not (Is-Array (Prop $node 'files'))){Fail "runs.$runName.nodes[].files must be an array"}else{foreach($file in (Prop $node 'files')){Require-Properties $file @('relative_path','category','length','last_write_utc') "runs.$runName.nodes[].files[]";Check-Allowed $file @('relative_path','category','length','last_write_utc') "runs.$runName.nodes[].files[]";$len=Prop $file 'length';if(-not ($len -is [int] -or $len -is [long]) -or [long]$len -lt 0){Fail 'file length must be a nonnegative integer'};$ft=[datetime]::MinValue;if(-not [datetime]::TryParse([string](Prop $file 'last_write_utc'),[ref]$ft)){Fail 'file last_write_utc must be an ISO date-time'}}}}}}
    $report=Prop $data 'report';$arrays=@('limitations','node_summary','server_comparison','gc_comparison','smaps_end','config_changes','database_summary','sql_comparison','awr_summary','instance_summary','ndump_summary','cmb_summary','artifact_coverage','errors_warnings','details')
    $reportNames=@($arrays)+@('executive_summary');Require-Properties $report $reportNames 'report';Check-Allowed $report $reportNames 'report';foreach($a in $arrays){if(-not(Is-Array(Prop $report $a))){Fail "report.$a must be an array"}};$exec=Prop $report 'executive_summary';$execFields=@('overall_status','top_regressions','improvements','plan_changes','new_errors','config_correlations','limitations_routes');Require-Properties $exec $execFields 'report.executive_summary';Check-Allowed $exec $execFields 'report.executive_summary';$status=Prop $exec 'overall_status';if($status-notin@('None','Low','Medium','High')){Fail 'report.executive_summary.overall_status must be a valid severity'};foreach($n in $execFields|Where-Object{$_-ne'overall_status'}){$items=Prop $exec $n;if(-not(Is-Array $items)){Fail "report.executive_summary.$n must be an array"}else{foreach($item in @($items)){if(-not($item-is[string])-or[string]::IsNullOrWhiteSpace($item)){Fail "report.executive_summary.$n items must be non-empty strings"}}}}
    $nodeFields=@('node','baseline_used_mb','current_used_mb','delta_used_mb','baseline_avg_rss_mb','current_avg_rss_mb','delta_avg_rss_mb','baseline_end_rss_mb','current_end_rss_mb','delta_end_rss_mb','baseline_avg_memavailable_mb','current_avg_memavailable_mb','delta_memavailable_mb','java_avg_rss_delta_mb','source_paths');Check-Rows (Prop $report 'node_summary') 'node_summary' @('node','source_paths') @('node') $nodeFields -Paired;foreach($row in (Prop $report 'node_summary')){if(-not((Prop $row 'node')-is[string])-or[string]::IsNullOrWhiteSpace([string](Prop $row 'node'))){Fail 'report.node_summary.node must be a non-empty string'};Check-Triplet $row 'baseline_used_mb' 'current_used_mb' 'delta_used_mb' 'report.node_summary'}
        Check-Rows (Prop $report 'config_changes') 'config_changes' @('node','server_id','property','source_paths') @('node','server_id','property') @() -Provenanced
    Check-Rows (Prop $report 'artifact_coverage') 'artifact_coverage' @('run','node','category','source_paths') @('run','node','category') @() -Provenanced
    Check-Rows (Prop $report 'errors_warnings') 'errors_warnings' @('run','node','category','server_database','timestamp','signature_message','source_paths') @('run','node','category','server_database','timestamp','signature_message') @() -Provenanced
    Check-Rows (Prop $report 'details') 'details' @('server_id','source_paths') @('server_id') @() -Provenanced
    $assessmentFields=@('assessment','source_paths')
    $server=@('node','server_id','baseline_avg_rss_mb','current_avg_rss_mb','delta_avg_rss_mb')+$assessmentFields
    Check-Rows (Prop $report 'server_comparison') 'server_comparison' @('node','server_id','baseline_avg_rss_mb','current_avg_rss_mb','delta_avg_rss_mb','source_paths','assessment') @('node','server_id') $server -Assessed -Provenanced
    $gc=@('node','server_id','baseline_final_after_gc_mb','current_final_after_gc_mb','delta_after_gc_mb')+$assessmentFields
    Check-Rows (Prop $report 'gc_comparison') 'gc_comparison' @('node','server_id','baseline_final_after_gc_mb','current_final_after_gc_mb','delta_after_gc_mb','source_paths','assessment') @('node','server_id') $gc -Assessed -Provenanced
    $smaps=@('node','server_id','baseline_rss_mb','current_rss_mb','delta_rss_mb','baseline_pss_mb','current_pss_mb','delta_pss_mb','baseline_private_dirty_mb','current_private_dirty_mb','delta_private_dirty_mb','delta_shared_clean_mb','source_paths','assessment');Check-Rows (Prop $report 'smaps_end') 'smaps_end' @('node','server_id','baseline_pss_mb','current_pss_mb','delta_pss_mb','source_paths','assessment') @('node','server_id') $smaps -Assessed -Provenanced
    $inst=@('node','server_instance_id','name','baseline_configured_instances','current_configured_instances','baseline_observed_instances','current_observed_instances','delta_instances','baseline_xms_mb','current_xms_mb','baseline_xmx_mb','current_xmx_mb','baseline_collector','current_collector','baseline_gc_logging','current_gc_logging','source_paths','assessment');Check-Rows (Prop $report 'instance_summary') 'instance_summary' @('node','server_instance_id','name','source_paths','assessment') @('node','server_instance_id') $inst -Assessed -Provenanced
        $db=@('database','instance','node','metric','baseline','current','delta','unit')+$assessmentFields
    Check-Rows (Prop $report 'database_summary') 'database_summary' $db @('database','instance','metric') $db -Assessed -Provenanced
    $sql=@('database','sql_id','plan_hash','module_schema','executions_baseline','executions_current','elapsed_baseline_ms','elapsed_current_ms','elapsed_delta_pct','cpu_baseline_ms','cpu_current_ms','buffer_gets_baseline','buffer_gets_current','disk_reads_baseline','disk_reads_current','rows_baseline','rows_current','avg_elapsed_baseline_ms','avg_elapsed_current_ms','source_paths','assessment')
    Check-Rows (Prop $report 'sql_comparison') 'sql_comparison' @('database','sql_id','plan_hash','executions_baseline','executions_current','avg_elapsed_baseline_ms','avg_elapsed_current_ms','source_paths','assessment') @('database','sql_id','plan_hash') $sql -Assessed -Provenanced
    $awr=@('database','instance','metric_wait_event','baseline','current','delta','unit','baseline_period','current_period','baseline_duration_minutes','current_duration_minutes','baseline_workload','current_workload','qualification','source_paths','assessment')
    Check-Rows (Prop $report 'awr_summary') 'awr_summary' $awr @('database','instance','metric_wait_event','baseline_period','current_period') $awr -Assessed -Provenanced
    $nd=@('node','server_instance','baseline_file_count','current_file_count','delta_count','baseline_total_mb','current_total_mb','delta_mb','latest_baseline_timestamp','latest_current_timestamp','signature_error','source_paths','assessment')
    Check-Rows (Prop $report 'ndump_summary') 'ndump_summary' @('node','server_instance','baseline_file_count','current_file_count','delta_count','baseline_total_mb','current_total_mb','delta_mb','source_paths','assessment') @('node','server_instance') $nd -Assessed -Provenanced
    $cmb=@('node','server_id','baseline_file_count','current_file_count','delta_count','baseline_total_mb','current_total_mb','delta_mb','baseline_warnings_errors','current_warnings_errors','key_difference','source_paths','assessment')
    Check-Rows (Prop $report 'cmb_summary') 'cmb_summary' @('node','server_id','baseline_file_count','current_file_count','delta_count','baseline_total_mb','current_total_mb','delta_mb','baseline_warnings_errors','current_warnings_errors','source_paths','assessment') @('node','server_id') $cmb -Assessed -Provenanced
    foreach($name in @('server_comparison','gc_comparison','database_summary','awr_summary')){foreach($r in (Prop $report $name)){if($name -eq 'server_comparison'){Check-Triplet $r 'baseline_avg_rss_mb' 'current_avg_rss_mb' 'delta_avg_rss_mb' "report.$name"}elseif($name -eq 'gc_comparison'){Check-Triplet $r 'baseline_final_after_gc_mb' 'current_final_after_gc_mb' 'delta_after_gc_mb' "report.$name"}else{Check-Triplet $r 'baseline' 'current' 'delta' "report.$name"}}}
    foreach($r in (Prop $report 'smaps_end')){Check-Triplet $r 'baseline_pss_mb' 'current_pss_mb' 'delta_pss_mb' 'report.smaps_end';Check-Triplet $r 'baseline_private_dirty_mb' 'current_private_dirty_mb' 'delta_private_dirty_mb' 'report.smaps_end'}
    foreach($r in (Prop $report 'instance_summary')){Check-Triplet $r 'baseline_configured_instances' 'current_configured_instances' 'delta_instances' 'report.instance_summary'}
    foreach($name in @('ndump_summary','cmb_summary')){foreach($r in (Prop $report $name)){Check-Triplet $r 'baseline_file_count' 'current_file_count' 'delta_count' "report.$name";Check-Triplet $r 'baseline_total_mb' 'current_total_mb' 'delta_mb' "report.$name"}}
    foreach($r in (Prop $report 'awr_summary')){$q=[string](Prop $r 'qualification');if([string]::IsNullOrWhiteSpace($q)){Fail 'report.awr_summary qualification must be non-empty'};$bd=[double](Prop $r 'baseline_duration_minutes');$cd=[double](Prop $r 'current_duration_minutes');$bw=[double](Prop $r 'baseline_workload');$cw=[double](Prop $r 'current_workload');$duration=if($bd){[Math]::Abs(($cd-$bd)/$bd)*100}else{100};$workload=if($bw){[Math]::Abs(($cw-$bw)/$bw)*100}else{100};if(($duration -gt [double]$thresholds.awr.duration_tolerance_pct -or $workload -gt [double]$thresholds.awr.workload_tolerance_pct) -and $q -match '^Comparable'){Fail 'report.awr_summary qualification must disclose mismatched period duration or workload'}}
    if($script:Errors.Count){foreach($e in $script:Errors){Write-Output "FAIL: $e"};exit 1}
    Write-Output 'PASS: canonical report schema v2';exit 0
}catch{Write-Output "FAIL: $($_.Exception.Message)";exit 1}











