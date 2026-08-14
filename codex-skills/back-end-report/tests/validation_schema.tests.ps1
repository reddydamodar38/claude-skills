$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
$validator = Join-Path $root 'scripts\validate_report_data.ps1'
$temp = Join-Path ([IO.Path]::GetTempPath()) ("back-end-validation-{0}" -f [guid]::NewGuid())
New-Item -ItemType Directory -Path $temp | Out-Null

function Assert-True($Condition, [string]$Message) { if (-not $Condition) { throw "FAIL: $Message" } }
function New-Assessment { [ordered]@{ severity='Medium'; confidence='High'; evidence=@('baseline=10; current=20; delta=10'); likely_cause='Observed increase'; route='Review source artifact' } }
function New-ValidDocument {
    [ordered]@{
        schema_version='2.0'; generated_utc='2026-07-02T12:00:00Z'
        runs=[ordered]@{
            baseline=[ordered]@{ path='C:\runs\base'; nodes=@([ordered]@{name='APP01';files=@([ordered]@{relative_path='memory.csv';category='server-memory';length=12;last_write_utc='2026-07-01T12:00:00Z'})}) }
            current=[ordered]@{ path='C:\runs\current'; nodes=@([ordered]@{name='APP01';files=@([ordered]@{relative_path='memory.csv';category='server-memory';length=14;last_write_utc='2026-07-02T12:00:00Z'})}) }
        }
        report=[ordered]@{
            limitations=@(); node_summary=@(); gc_comparison=@(); smaps_end=@(); config_changes=@(); database_summary=@(); sql_comparison=@(); awr_summary=@(); instance_summary=@(); ndump_summary=@(); cmb_summary=@(); artifact_coverage=@(); errors_warnings=@(); details=@()
            executive_summary=[ordered]@{overall_status='Low';top_regressions=@();improvements=@();plan_changes=@();new_errors=@();config_correlations=@();limitations_routes=@()}
            server_comparison=@([ordered]@{ node='APP01';server_id='S1';baseline_avg_rss_mb=10.0;current_avg_rss_mb=20.0;delta_avg_rss_mb=10.0;source_paths=@('baseline:APP01/memory.csv','current:APP01/memory.csv');assessment=(New-Assessment) })
        }
    }
}
function Write-Doc($Doc,[string]$Name) { $p=Join-Path $temp $Name; $Doc|ConvertTo-Json -Depth 20|Set-Content -LiteralPath $p -Encoding UTF8; $p }
function Invoke-Validation([string]$Path) { & $validator -DataPath $Path 2>&1 | Out-String; $LASTEXITCODE }

try {
    $valid=Write-Doc (New-ValidDocument) 'valid.json'
    $output=& $validator -DataPath $valid 2>&1 | Out-String
    Assert-True ($LASTEXITCODE -eq 0) "valid v2 document was rejected: $output"

    $duplicate=New-ValidDocument
    $duplicate.report.server_comparison += $duplicate.report.server_comparison[0]
    $p=Write-Doc $duplicate 'duplicate.json'; $output=& $validator -DataPath $p 2>&1|Out-String
    Assert-True ($LASTEXITCODE -ne 0 -and $output -match 'duplicate stable key') 'duplicate stable keys were not rejected'

    $badDelta=New-ValidDocument
    $badDelta.report.server_comparison[0].current_avg_rss_mb=$null
    $p=Write-Doc $badDelta 'bad-delta.json'; $output=& $validator -DataPath $p 2>&1|Out-String
    Assert-True ($LASTEXITCODE -ne 0 -and $output -match 'delta.*must be null') 'delta was allowed when one side was unavailable'

    $zero=New-ValidDocument
    $zero.report.server_comparison[0].baseline_avg_rss_mb=0
    $zero.report.server_comparison[0].source_paths=@('current:APP01/memory.csv')
    $p=Write-Doc $zero 'missing-as-zero.json'; $output=& $validator -DataPath $p 2>&1|Out-String
    Assert-True ($LASTEXITCODE -ne 0 -and $output -match 'missing data.*zero') 'missing baseline data represented as zero was not rejected'

    $awr=New-ValidDocument
    $awr.report.server_comparison=@()
    $awr.report.awr_summary=@([ordered]@{database='DB1';instance='1';metric_wait_event='DB CPU';baseline=10;current=20;delta=10;unit='seconds';baseline_period='B1-B2';current_period='C1-C2';baseline_duration_minutes=60;current_duration_minutes=30;baseline_workload=100;current_workload=100;qualification='Comparable';source_paths=@('baseline:APP01/awr.txt','current:APP01/awr.txt');assessment=(New-Assessment)})
    $p=Write-Doc $awr 'bad-awr.json'; $output=& $validator -DataPath $p 2>&1|Out-String
    Assert-True ($LASTEXITCODE -ne 0 -and $output -match 'qualification') 'mismatched AWR periods were accepted as comparable'

    Write-Output 'PASS: validation schema tests'
} finally { Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue }


