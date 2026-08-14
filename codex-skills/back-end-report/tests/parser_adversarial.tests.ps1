$ErrorActionPreference='Stop';$root=Split-Path -Parent $PSScriptRoot;$t=Join-Path $env:TEMP ('parser-adv-'+[guid]::NewGuid().ToString('N'))
function A($v,$m){if(-not$v){throw "ASSERT: $m"}};function E($e,$a,$m){if($e-ne$a){throw "ASSERT: $m expected=$e actual=$a"}}
try{foreach($run in @('b','c')){mkdir (Join-Path $t "$run\N1") -Force|Out-Null};$b=Join-Path $t 'b\N1';$c=Join-Path $t 'c\N1'
Set-Content "$b\server_memory.csv" "server_id,pid,rss_mb`nSCP1,1,100`nSCP1,2,300";Set-Content "$c\server_memory.csv" "server_id,pid,rss_mb`nSCP1,9,300`nSCP1,8,500"
Set-Content "$b\gc_SCP1.log" "[Full GC 300M->200M(512M), 0.100 secs]`n[GC pause (G1 Evacuation Pause) 400M->250M(512M) 0.050 secs]";Set-Content "$c\gc_SCP1.log" "[Full GC 400M->220M(600M), 0.120 secs]`n[2.0s][info][gc] GC(2) Pause Young 500M->280M(600M) 70ms"
Set-Content "$b\scps_1_smaps_end.txt" "Pss: 100 kB`nPss: 200 kB`nPrivate_Dirty: 50 kB`nPrivate_Dirty: 70 kB";Set-Content "$c\scps_1_smaps_end.txt" "Pss: 400 kB`nPrivate_Dirty: 180 kB"
Set-Content "$b\regdump.txt" "SCP1.jvmargs = -Xms1024K -Xmx2G";Set-Content "$c\regdump.txt" "SCP1.jvmargs = -Xms2M -Xmx3G"
1..2|%{Set-Content "$b\ndump_SCP1_$_.log" "ORA-00600 case $_";Set-Content "$b\cmb_1_$_.log" "WARN case $_"};1..3|%{Set-Content "$c\ndump_SCP1_$_.log" "ORA-07445 case $_";Set-Content "$c\cmb_1_$_.log" "ERROR case $_"}
Set-Content "$b\sql_stats.csv" "database,sql_id,plan_hash,executions,elapsed_ms,cpu_ms,buffer_gets,disk_reads,rows`nDB,q1,10,2,100,50,2,1,2`nDB,q1,11,3,300,100,3,1,3";Set-Content "$c\sql_stats.csv" "database,sql_id,plan_hash,executions,elapsed_ms,cpu_ms,buffer_gets,disk_reads,rows`nDB,q1,12,5,1000,300,5,2,5"
Set-Content "$b\awr_report.txt" "Database: DB`nInstance: I1`nSnapshot Begin: 1 End: 2`nDuration: 60 minutes`nExecutions: 100`nDB Time: 10";Set-Content "$c\awr_report.txt" "Database: DB`nInstance: I1`nSnapshot Begin: 2 End: 3`nDuration: 60 minutes`nExecutions: 200`nDB Time: 20"
$out=Join-Path $t output;& "$root\scripts\build_report.ps1" -BaselinePath (Join-Path $t b)-CurrentPath (Join-Path $t c)-OutputDirectory $out -JsonOnly;$d=gc -Raw (Join-Path $out 'back-end-report.json')|ConvertFrom-Json
E 200 ([double]$d.report.server_comparison[0].baseline_avg_rss_mb) 'RSS samples average';E 200 ([double]$d.report.server_comparison[0].delta_avg_rss_mb) 'RSS delta'
E 250 ([double]$d.report.gc_comparison[0].baseline_final_after_gc_mb) 'final after-GC retained'
E 0.29296875 ([double]$d.report.smaps_end[0].baseline_pss_mb) 'smaps mappings summed';E 1 ([double]$d.report.instance_summary[0].baseline_xms_mb) 'K converted';E 2048 ([double]$d.report.instance_summary[0].baseline_xmx_mb) 'G converted'
E 2 ([int]$d.report.ndump_summary[0].baseline_file_count) 'ndumps aggregated';E 3 ([int]$d.report.cmb_summary[0].current_file_count) 'CMB aggregated'
E 3 (@($d.report.sql_comparison).Count) 'SQL plans remain separate';A ($null-eq($d.report.sql_comparison|? plan_hash -eq 10).executions_current) 'removed plan remains null on current side'
A ($d.report.awr_summary[0].qualification-match'workload' -and $d.report.awr_summary[0].qualification-notmatch'duration differs') 'workload independently qualified';A (@($d.report.server_comparison[0].source_paths).Count-eq2) 'side provenance preserved'
'PASS: adversarial parser aggregation and formats'}finally{rm $t -Recurse -Force -ErrorAction SilentlyContinue}
