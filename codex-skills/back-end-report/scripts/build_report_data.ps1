param(
    [Parameter(Mandatory=$true)][string]$BaselineDataPath,
    [Parameter(Mandatory=$true)][string]$CurrentDataPath,
    [Parameter(Mandatory=$true)][string]$OutputPath
)
$ErrorActionPreference='Stop'
$baseline=Get-Content -Raw -LiteralPath $BaselineDataPath|ConvertFrom-Json
$current=Get-Content -Raw -LiteralPath $CurrentDataPath|ConvertFrom-Json

function Rows($data,[string]$kind){@($data.records|Where-Object kind -eq $kind)}
function V($row,[string]$name){if($null-eq$row){return $null};$p=$row.values.PSObject.Properties[$name];if($p){$p.Value}else{$null}}
function D($before,$after){if($null-ne$before-and$null-ne$after){[double]$after-[double]$before}else{$null}}
function First($rows,[string]$name){foreach($row in @($rows)){$v=V $row $name;if($null-ne$v){return $v}};$null}
function Sum($rows,[string]$name){$values=@($rows|ForEach-Object{V $_ $name}|Where-Object{$null-ne$_});if(!$values.Count){return $null};[double]($values|Measure-Object -Sum).Sum}
function Average($rows,[string]$name){$values=@($rows|ForEach-Object{V $_ $name}|Where-Object{$null-ne$_});if(!$values.Count){return $null};[double]($values|Measure-Object -Average).Average}
function Last($rows,[string]$name){$values=@($rows|ForEach-Object{V $_ $name}|Where-Object{$null-ne$_});if(!$values.Count){return $null};$values[-1]}
function Placeholder{[pscustomobject][ordered]@{severity='None';confidence='Low';evidence=@('Assessment pending');likely_cause='No assessment has been calculated';route='Validate and assess the canonical report'}}
function SideSources([string]$side,$rows){@($rows|ForEach-Object{$_.source}|Where-Object{$_}|Sort-Object -Unique|ForEach-Object{"${side}:$_"})}
function Sources($b,$c,$fallbackB,$fallbackC){$bs=@(SideSources baseline $b);$cs=@(SideSources current $c);if(!$bs.Count-and$fallbackB){$bs=@(SideSources baseline $fallbackB)};if(!$cs.Count-and$fallbackC){$cs=@(SideSources current $fallbackC)};@($bs+$cs|Sort-Object -Unique)}
function InventoryNodeMap($data){$map=@{};foreach($g in @($data.inventory|Group-Object node)){if($g.Name){$map[[string]$g.Name]=@($g.Group.relative_path|Where-Object{$_}|Sort-Object)}};$map}
function InventoryNodeSource($map,[string]$side,[string]$node){if(!$map.ContainsKey($node)){return $null};$paths=@($map[$node]);if(!$paths.Count){return $null};$preferred=@($paths|Where-Object{$_ -match '(?i)(meminfo|memory|nmon)'});$path=if($preferred.Count){$preferred[0]}else{$paths[0]};"${side}:$path"}
function Groups($rows,[scriptblock]$key){$map=@{};if($null-eq$key){return $map};foreach($row in @($rows)){if($null-eq$row-or$null-eq$row.PSObject.Properties['kind']){continue};$k=[string](&$key $row);if([string]::IsNullOrWhiteSpace($k)){$k='__EMPTY__|'+[string]$row.node+'|'+[string]$row.source};if(!$map.ContainsKey($k)){$map[$k]=New-Object Collections.ArrayList};[void]$map[$k].Add($row)};$map}
function Keys($left,$right){@($left.Keys+$right.Keys|Where-Object{$_}|Sort-Object -Unique)}
function GetGroup($map,[string]$key){if($map.ContainsKey($key)){@($map[$key])}else{@()}}

$report=[ordered]@{
 limitations=@(
  'GC parsing supports same-line heap before/after transitions with ms or secs pause values.',
  'AWR workload parsing recognizes an Executions line and DB Time/DB CPU summary metrics.',
  'SQL statistics parsing expects CSV headers including database, sql_id, plan_hash, executions, and elapsed_ms.',
  'Safe ZIP members are inventoried with traversal and size limits; contained artifacts are not parsed.',
  'JVM heap-size normalization supports K, M, and G suffixes.'
 );executive_summary=[ordered]@{overall_status='None';top_regressions=@();improvements=@();plan_changes=@();new_errors=@();config_correlations=@();limitations_routes=@()}
 node_summary=@();server_comparison=@();gc_comparison=@();smaps_end=@();config_changes=@();database_summary=@();sql_comparison=@();awr_summary=@();instance_summary=@();ndump_summary=@();cmb_summary=@();artifact_coverage=@();errors_warnings=@();details=@()
}

# Node and process memory
$bg=Groups (Rows $baseline node-memory){param($x)[string]$x.node};$cg=Groups (Rows $current node-memory){param($x)[string]$x.node}
$bNodeInventory=InventoryNodeMap $baseline;$cNodeInventory=InventoryNodeMap $current
foreach($k in Keys $bg $cg){if(!$bNodeInventory.ContainsKey($k)-or!$cNodeInventory.ContainsKey($k)){continue};$br=@(GetGroup $bg $k);$cr=@(GetGroup $cg $k);$b=Average $br used_mb;$c=Average $cr used_mb;$paths=@(Sources $br $cr $null $null);if(!@($paths|Where-Object{$_ -like 'baseline:*'}).Count){$paths+=InventoryNodeSource $bNodeInventory baseline $k};if(!@($paths|Where-Object{$_ -like 'current:*'}).Count){$paths+=InventoryNodeSource $cNodeInventory current $k};$report.node_summary+=,[ordered]@{node=$k;baseline_used_mb=$b;current_used_mb=$c;delta_used_mb=D $b $c;source_paths=@($paths|Where-Object{$_}|Sort-Object -Unique)}}
$bg=Groups (Rows $baseline server-memory){param($x)('{0}|{1}'-f$x.node,(V $x server_id))};$cg=Groups (Rows $current server-memory){param($x)('{0}|{1}'-f$x.node,(V $x server_id))}
foreach($k in Keys $bg $cg){$br=@(GetGroup $bg $k);$cr=@(GetGroup $cg $k);$q=if($cr.Count){$cr[0]}else{$br[0]};$b=Average $br rss_mb;$c=Average $cr rss_mb;$report.server_comparison+=,[ordered]@{node=$q.node;server_id=V $q server_id;baseline_avg_rss_mb=$b;current_avg_rss_mb=$c;delta_avg_rss_mb=D $b $c;source_paths=@(Sources $br $cr $null $null);assessment=Placeholder}}

# GC and smaps
$bg=Groups (Rows $baseline gc){param($x)('{0}|{1}'-f$x.node,(V $x server_id))};$cg=Groups (Rows $current gc){param($x)('{0}|{1}'-f$x.node,(V $x server_id))}
foreach($k in Keys $bg $cg){$br=@(GetGroup $bg $k);$cr=@(GetGroup $cg $k);$q=if($cr.Count){$cr[0]}else{$br[0]};$b=Last $br after_gc_mb;$c=Last $cr after_gc_mb;$report.gc_comparison+=,[ordered]@{node=$q.node;server_id=V $q server_id;baseline_final_after_gc_mb=$b;current_final_after_gc_mb=$c;delta_after_gc_mb=D $b $c;source_paths=@(Sources $br $cr $null $null);assessment=Placeholder}}
$bg=Groups (Rows $baseline smaps){param($x)('{0}|{1}'-f$x.node,(V $x server_id))};$cg=Groups (Rows $current smaps){param($x)('{0}|{1}'-f$x.node,(V $x server_id))}
foreach($k in Keys $bg $cg){$br=@(GetGroup $bg $k);$cr=@(GetGroup $cg $k);$q=if($cr.Count){$cr[0]}else{$br[0]};$bpss=Sum $br pss_mb;$cpss=Sum $cr pss_mb;$bpd=Sum $br private_dirty_mb;$cpd=Sum $cr private_dirty_mb;$report.smaps_end+=,[ordered]@{node=$q.node;server_id=V $q server_id;baseline_rss_mb=$null;current_rss_mb=$null;delta_rss_mb=$null;baseline_pss_mb=$bpss;current_pss_mb=$cpss;delta_pss_mb=D $bpss $cpss;baseline_private_dirty_mb=$bpd;current_private_dirty_mb=$cpd;delta_private_dirty_mb=D $bpd $cpd;delta_shared_clean_mb=$null;source_paths=@(Sources $br $cr $null $null);assessment=Placeholder}}

# Configuration and instances
$bc=Groups (Rows $baseline config){param($x)$x.key};$cc=Groups (Rows $current config){param($x)$x.key};$bi=Groups (Rows $baseline instances){param($x)$x.key};$ci=Groups (Rows $current instances){param($x)$x.key}
foreach($k in Keys $bc $cc){$br=@(GetGroup $bc $k);$cr=@(GetGroup $cc $k);$bir=@(GetGroup $bi $k);$cir=@(GetGroup $ci $k);$q=if($cr.Count){$cr[0]}else{$br[0]};$bid=First $bir configured_instances;$cid=First $cir configured_instances;$id=V $q server_id;$paths=@(Sources ($br+$bir) ($cr+$cir) $null $null);$report.instance_summary+=,[ordered]@{node=$q.node;server_instance_id=$id;name=$id;baseline_configured_instances=$bid;current_configured_instances=$cid;baseline_observed_instances=$null;current_observed_instances=$null;delta_instances=D $bid $cid;baseline_xms_mb=First $br xms_mb;current_xms_mb=First $cr xms_mb;baseline_xmx_mb=First $br xmx_mb;current_xmx_mb=First $cr xmx_mb;baseline_collector=First $br collector;current_collector=First $cr collector;baseline_gc_logging=First $br gc_logging;current_gc_logging=First $cr gc_logging;source_paths=$paths;assessment=Placeholder};foreach($property in @('jvmargs','configured_instances')){$bv=if($property-eq'configured_instances'){$bid}else{First $br $property};$cv=if($property-eq'configured_instances'){$cid}else{First $cr $property};if($bv-ne$cv){$report.config_changes+=,[ordered]@{node=$q.node;server_id=$id;property=$property;baseline=$bv;current=$cv;source_paths=$paths}}}}

# Database
$bg=Groups (Rows $baseline database){param($x)$x.key};$cg=Groups (Rows $current database){param($x)$x.key}
foreach($k in Keys $bg $cg){$br=@(GetGroup $bg $k);$cr=@(GetGroup $cg $k);$q=if($cr.Count){$cr[-1]}else{$br[-1]};$b=First $br value;$c=First $cr value;$report.database_summary+=,[ordered]@{database=V $q database;instance=V $q instance;node=$q.node;metric=V $q metric;baseline=$b;current=$c;delta=D $b $c;unit=V $q unit;source_paths=@(Sources $br $cr $null $null);assessment=Placeholder}}

# SQL is compared per plan; an opposite-side SQL artifact is evidence that a plan is absent.
$allB=@(Rows $baseline sql);$allC=@(Rows $current sql)
$bg=Groups $allB{param($x)('{0}|{1}|{2}'-f(V $x database),(V $x sql_id),(V $x plan_hash))};$cg=Groups $allC{param($x)('{0}|{1}|{2}'-f(V $x database),(V $x sql_id),(V $x plan_hash))}
foreach($k in Keys $bg $cg){$br=@(GetGroup $bg $k);$cr=@(GetGroup $cg $k);$q=if($cr.Count){$cr[0]}else{$br[0]};$db=V $q database;$sql=V $q sql_id;$fallbackB=@($allB|Where-Object{(V $_ database)-eq$db-and(V $_ sql_id)-eq$sql});$fallbackC=@($allC|Where-Object{(V $_ database)-eq$db-and(V $_ sql_id)-eq$sql});$be=Sum $br executions;$ce=Sum $cr executions;$bt=Sum $br elapsed_ms;$ct=Sum $cr elapsed_ms;$ba=if($null-ne$be-and[double]$be-ne0-and$null-ne$bt){[double]$bt/[double]$be}else{$null};$ca=if($null-ne$ce-and[double]$ce-ne0-and$null-ne$ct){[double]$ct/[double]$ce}else{$null};$pct=if($null-ne$ba-and[double]$ba-ne0-and$null-ne$ca){(([double]$ca-[double]$ba)/[Math]::Abs([double]$ba))*100}else{$null};$report.sql_comparison+=,[ordered]@{database=$db;sql_id=$sql;plan_hash=V $q plan_hash;module_schema=First ($br+$cr) module_schema;executions_baseline=$be;executions_current=$ce;elapsed_baseline_ms=$bt;elapsed_current_ms=$ct;elapsed_delta_pct=$pct;cpu_baseline_ms=Sum $br cpu_ms;cpu_current_ms=Sum $cr cpu_ms;buffer_gets_baseline=Sum $br buffer_gets;buffer_gets_current=Sum $cr buffer_gets;disk_reads_baseline=Sum $br disk_reads;disk_reads_current=Sum $cr disk_reads;rows_baseline=Sum $br rows;rows_current=Sum $cr rows;avg_elapsed_baseline_ms=$ba;avg_elapsed_current_ms=$ca;source_paths=@(Sources $br $cr $fallbackB $fallbackC);assessment=Placeholder}}

# AWR
$bg=Groups (Rows $baseline awr){param($x)$x.key};$cg=Groups (Rows $current awr){param($x)$x.key}
foreach($k in Keys $bg $cg){$br=@(GetGroup $bg $k);$cr=@(GetGroup $cg $k);$q=if($cr.Count){$cr[-1]}else{$br[-1]};$b=First $br value;$c=First $cr value;$bd=First $br duration_minutes;$cd=First $cr duration_minutes;$bw=First $br workload;$cw=First $cr workload;$qual=if($null-eq$bd-or$null-eq$cd-or$null-eq$bw-or$null-eq$cw){'Qualified: duration or workload unavailable'}elseif([double]$bd-ne[double]$cd-and[double]$bw-ne[double]$cw){'Qualified: duration and workload differ'}elseif([double]$bd-ne[double]$cd){'Qualified: duration differs'}elseif([double]$bw-ne[double]$cw){'Qualified: workload differs'}else{'Comparable duration and workload'};$report.awr_summary+=,[ordered]@{database=V $q database;instance=V $q instance;baseline_period=First $br period;current_period=First $cr period;metric_wait_event=V $q metric;baseline=$b;current=$c;delta=D $b $c;unit=V $q unit;baseline_duration_minutes=$bd;current_duration_minutes=$cd;baseline_workload=$bw;current_workload=$cw;qualification=$qual;source_paths=@(Sources $br $cr $null $null);assessment=Placeholder}}

# Diagnostic and CMB summaries
foreach($kind in @('ndump','cmb')){$allB=@(Rows $baseline $kind);$allC=@(Rows $current $kind);$bg=Groups $allB{param($x)$x.key};$cg=Groups $allC{param($x)$x.key};foreach($k in Keys $bg $cg){$br=@(GetGroup $bg $k);$cr=@(GetGroup $cg $k);$q=if($cr.Count){$cr[0]}else{$br[0]};$bc=if($br.Count){$br.Count}else{$null};$cc=if($cr.Count){$cr.Count}else{$null};$bm=Sum $br size_mb;$cm=Sum $cr size_mb;$common=[ordered]@{node=$q.node;baseline_file_count=$bc;current_file_count=$cc;delta_count=D $bc $cc;baseline_total_mb=$bm;current_total_mb=$cm;delta_mb=D $bm $cm;source_paths=@(Sources $br $cr $allB $allC);assessment=Placeholder};if($kind-eq'ndump'){$common.server_instance=V $q server_instance;$common.latest_baseline_timestamp=$null;$common.latest_current_timestamp=$null;$common.signature_error=@($br+$cr|ForEach-Object{V $_ signature}|Where-Object{$_}|Sort-Object -Unique)-join'; ';$report.ndump_summary+=,$common}else{$common.server_id=V $q server_id;$common.baseline_warnings_errors=Sum $br warnings_errors;$common.current_warnings_errors=Sum $cr warnings_errors;$common.key_difference='';$report.cmb_summary+=,$common}}}

# Coverage. Parser errors remain preserved when present.
foreach($data in @($baseline,$current)){$side=[string]$data.run;foreach($g in @($data.inventory|Group-Object node,category|Sort-Object Name)){$f=$g.Group[0];$duplicateCount=@($g.Group|Where-Object is_duplicate).Count;$memberCount=@($data.zip_entries|Where-Object{$g.Group.relative_path -contains $_.source}).Count;$report.artifact_coverage+=,[ordered]@{run=$side;node=$f.node;category=$f.category;file_count=$g.Count;total_mb=[double](($g.Group|Measure-Object length -Sum).Sum/1MB);latest_timestamp=@($g.Group.last_write_utc|Sort-Object)[-1];status=('Present; duplicates={0}; zip_members={1}' -f $duplicateCount,$memberCount);source_paths=@($g.Group.relative_path|Sort-Object|ForEach-Object{"${side}:$_"})}}}

foreach($data in @($baseline,$current)){
 $side=[string]$data.run
 foreach($entry in @($data.errors)){
  $source=if($entry.source){[string]$entry.source}else{'(parser)'}
  $report.errors_warnings+=,[ordered]@{run=$side;node=if($entry.node){[string]$entry.node}else{'(root)'};category=if($entry.category){[string]$entry.category}else{'parser'};server_database=if($entry.server_database){[string]$entry.server_database}else{''};timestamp=if($entry.timestamp){[string]$entry.timestamp}else{[DateTime]::UtcNow.ToString('o')};severity=if($entry.severity){[string]$entry.severity}else{'Warning'};signature_message=if($entry.signature_message){[string]$entry.signature_message}else{[string]$entry};count=if($entry.count){[int]$entry.count}else{1};source_paths=@("${side}:$source")}
 }
}
function NodeList($data){@($data.inventory|Group-Object node|Sort-Object Name|ForEach-Object{[ordered]@{name=[string]$_.Name;files=@($_.Group|Sort-Object relative_path|ForEach-Object{[ordered]@{relative_path=[string]$_.relative_path;category=[string]$_.category;length=[long]$_.length;last_write_utc=[string]$_.last_write_utc}})}})}
$report.executive_summary.limitations_routes=@($report.limitations)
$doc=[ordered]@{schema_version='2.0';generated_utc=[DateTime]::UtcNow.ToString('o');runs=[ordered]@{baseline=[ordered]@{path=$baseline.path;nodes=@(NodeList $baseline)};current=[ordered]@{path=$current.path;nodes=@(NodeList $current)}};report=$report}
$parent=Split-Path -Parent $OutputPath;if($parent){New-Item -ItemType Directory -Path $parent -Force|Out-Null}
$doc|ConvertTo-Json -Depth 30|Set-Content -LiteralPath $OutputPath -Encoding UTF8
