$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$scratch=Join-Path $env:TEMP ('back-end-parser-'+[guid]::NewGuid().ToString('N'))
function A($v,[string]$m){if(-not$v){throw "ASSERT: $m"}}
function E($e,$a,[string]$m){if($e-ne$a){throw "ASSERT: $m expected=$e actual=$a"}}
try{
 New-Item -ItemType Directory -Path $scratch|Out-Null
 $parsed=Join-Path $scratch 'parsed.json'
 & "$root\scripts\parse_artifacts.ps1" -RunPath "$PSScriptRoot\fixtures\baseline" -RunName baseline -OutputPath $parsed
 $p=Get-Content $parsed -Raw|ConvertFrom-Json
 $files=@($p.inventory)
 A ($files.Count-ge10) 'all artifacts inventoried'
 A (($files|Where-Object relative_path -eq 'NODE1\mystery.xyz').category-eq'unknown') 'unknown preserved'
 A (($files|Where-Object relative_path -eq 'NODE1\meminfo.txt').sha256-match'^[0-9a-f]{64}$') 'SHA-256 present'
 E (@($files|Sort-Object relative_path|ForEach-Object relative_path)-join'|') (@($files|ForEach-Object relative_path)-join'|') 'inventory deterministic'
 $out=Join-Path $scratch output
 & "$root\scripts\build_report.ps1" -BaselinePath "$PSScriptRoot\fixtures\baseline" -CurrentPath "$PSScriptRoot\fixtures\current" -OutputDirectory $out -JsonOnly
 $d=Get-Content (Join-Path $out 'back-end-report.json') -Raw|ConvertFrom-Json
 E '2.0' $d.schema_version 'schema version'
 A ($d.report.server_comparison[0].delta_avg_rss_mb-ge100) 'server memory compared by stable server key'
 A ($d.report.server_comparison[0].assessment.severity-in@('Medium','High')) 'memory severity assessed'
 A (@($d.report.database_summary).Count-ge4) 'database metrics parsed'
 A (@($d.report.sql_comparison|Where-Object sql_id -eq 'abc123').Count-ge1) 'SQL parsed per plan'
 A ($d.report.awr_summary[0].qualification-match'duration|workload|Comparable') 'AWR qualified'
 E 1 ([int]$d.report.ndump_summary[0].current_file_count) 'ndump grouped'
 E '397' ([string]$d.report.cmb_summary[0].server_id) 'CMB filename server mapping'
 A (@($d.report.errors_warnings).Count-ge4) 'warning/error signatures preserved'
 A (@($d.report.artifact_coverage|Where-Object category -eq 'unknown').Count-eq1) 'unknown coverage retained'
 'PASS: parser extraction and canonical normalization'
}finally{Remove-Item $scratch -Recurse -Force -ErrorAction SilentlyContinue}

