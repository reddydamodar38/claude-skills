$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$temp = Join-Path ([IO.Path]::GetTempPath()) ('back-end-parser-contract-' + [guid]::NewGuid())

function Assert($Condition, [string]$Message) { if (-not $Condition) { throw "ASSERT: $Message" } }

try {
    $baseline = Join-Path $temp 'baseline\NODE1'
    $current = Join-Path $temp 'current\NODE1'
    $output = Join-Path $temp 'output'
    New-Item -ItemType Directory -Path $baseline,$current,$output -Force | Out-Null

    Set-Content -LiteralPath (Join-Path $baseline 'meminfo.txt') -Value "MemTotal: 16777216 kB`nMemAvailable: 8388608 kB"
    Set-Content -LiteralPath (Join-Path $current 'meminfo.txt') -Value "MemTotal: 16777216 kB`nMemAvailable: 7340032 kB"
    Set-Content -LiteralPath (Join-Path $baseline 'server_memory.csv') -Value "server_id,pid,rss_mb,private_mb`nS1,1,100,50`nS1,2,300,150"
    Set-Content -LiteralPath (Join-Path $current 'server_memory.csv') -Value "server_id,pid,rss_mb,private_mb`nS1,3,200,100`nS1,4,400,200"
    Set-Content -LiteralPath (Join-Path $baseline 'gc_SCP1.log') -Value "100M->50M 0.1 secs`n120M->60M 20ms"
    Set-Content -LiteralPath (Join-Path $current 'gc_SCP1.log') -Value "140M->70M 0.2 secs`n160M->80M 40ms"
    Set-Content -LiteralPath (Join-Path $baseline 'scps_1_smaps_end.txt') -Value "Pss: 1024 kB`nPss: 2048 kB`nPrivate_Dirty: 1024 kB"
    Set-Content -LiteralPath (Join-Path $current 'scps_1_smaps_end.txt') -Value "Pss: 2048 kB`nPss: 2048 kB`nPrivate_Dirty: 2048 kB"
    Set-Content -LiteralPath (Join-Path $baseline 'regdump.txt') -Value "SCP1.jvmargs=-Xms1G -Xmx1048576K`nSCP1.instances=2"
    Set-Content -LiteralPath (Join-Path $current 'regdump.txt') -Value "SCP1.jvmargs=-Xms2048M -Xmx2G`nSCP1.instances=3"
    Set-Content -LiteralPath (Join-Path $baseline 'sql_stats.csv') -Value "database,sql_id,plan_hash,executions,elapsed_ms,cpu_ms,buffer_gets,disk_reads,rows`nDB1,abc,1,10,100,,,,`nDB1,abc,2,10,300,100,20,3,4"
    Set-Content -LiteralPath (Join-Path $current 'sql_stats.csv') -Value "database,sql_id,plan_hash,executions,elapsed_ms,cpu_ms,buffer_gets,disk_reads,rows`nDB1,abc,2,10,400,150,30,4,5"
    Set-Content -LiteralPath (Join-Path $baseline 'awr_report.txt') -Value "Database: DB1`nInstance: 1`nSnapshot Begin: 1 End: 2`nDuration: 60 minutes`nExecutions: 100`nDB Time: 50`nDB CPU: 25"
    Set-Content -LiteralPath (Join-Path $current 'awr_report.txt') -Value "Database: DB1`nInstance: 1`nSnapshot Begin: 3 End: 4`nDuration: 60 minutes`nExecutions: 200`nDB Time: 70`nDB CPU: 35"

    $builder = Join-Path $root 'scripts\build_report.ps1'
    $log = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $builder -BaselinePath (Split-Path -Parent $baseline) -CurrentPath (Split-Path -Parent $current) -OutputDirectory $output -JsonOnly 2>&1 | Out-String
    Assert ($LASTEXITCODE -eq 0) "end-to-end subprocess failed: $log"

    $data = Get-Content -Raw -LiteralPath (Join-Path $output 'back-end-report.json') | ConvertFrom-Json
    Assert ($data.runs.baseline.nodes -is [Array]) 'single baseline node must remain an array'
    Assert ($data.report.server_comparison[0].baseline_avg_rss_mb -eq 200) 'repeated server samples must average'
    Assert ($data.report.gc_comparison[0].baseline_final_after_gc_mb -eq 60) 'GC must retain final after-GC value'
    Assert ($data.report.smaps_end[0].baseline_pss_mb -eq 3) 'smaps entries must sum'
    Assert ($data.report.instance_summary[0].baseline_xms_mb -eq 1024) 'JVM units must normalize to MB'
    Assert (@($data.report.sql_comparison).Count -eq 2) 'SQL plans must remain separate rows'
    $missingPlan = $data.report.sql_comparison | Where-Object plan_hash -eq 1
    Assert ($null -eq $missingPlan.executions_current) 'one-sided SQL current metrics must remain null'
    Assert ($null -eq $missingPlan.cpu_baseline_ms) 'missing SQL metrics must remain null, not zero'
    Assert (@($missingPlan.source_paths | Where-Object { $_ -like 'baseline:*' }).Count -eq 1) 'baseline provenance must be side-prefixed'
    Assert (@($missingPlan.source_paths | Where-Object { $_ -like 'current:*' }).Count -eq 1) 'missing current side must have explicit provenance'
    Assert ($data.report.awr_summary[0].baseline_workload -eq 100) 'AWR baseline workload must be retained'
    Assert ($data.report.awr_summary[0].qualification -match 'workload') 'AWR workload mismatch must be qualified'
    Assert ($data.report.executive_summary.overall_status -ne 'Generated') 'executive summary must be assessed'
    Assert (@($data.report.limitations).Count -gt 0) 'supported parser format limitations must be explicit'
    Write-Output 'PASS: parser canonical contract'
} finally {
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}
