[CmdletBinding()]
param(
    [string]$Runner = 'root@dh2vpc067.dh2.cerner.com'
)

$ErrorActionPreference = 'Stop'

$skillRoot = Split-Path -Parent $PSScriptRoot
$parser = Join-Path $skillRoot 'scripts\summarize-status.sh'
$fixtures = Join-Path $PSScriptRoot 'fixtures'
$remoteRoot = '/root/codex-workspace/stale-stats-parser-tests'

if (-not (Test-Path -LiteralPath $parser)) {
    throw "Parser is missing: $parser"
}

$identity = & ssh $Runner 'hostname; id -un; pwd'
if ($LASTEXITCODE -ne 0) {
    throw "Unable to connect to Linux runner '$Runner'."
}
if (($identity -join "`n") -notmatch '(?m)^dh2vpc067(?:\.dh2\.cerner\.com)?$' -or
    ($identity -join "`n") -notmatch '(?m)^root$') {
    throw "Unexpected Linux runner identity: $($identity -join ', ')"
}

& ssh $Runner "mkdir -p '$remoteRoot/fixtures'"
if ($LASTEXITCODE -ne 0) {
    throw 'Unable to create the remote parser-test directory.'
}

& scp $parser "${Runner}:$remoteRoot/summarize-status.sh"
if ($LASTEXITCODE -ne 0) {
    throw 'Unable to copy the parser to the Linux runner.'
}

Get-ChildItem -LiteralPath $fixtures -File | ForEach-Object {
    & scp $_.FullName "${Runner}:$remoteRoot/fixtures/$($_.Name)"
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to copy fixture '$($_.Name)' to the Linux runner."
    }
}

$cases = @(
    @{ File = 'published.txt';              Exit = 0; Token = 'STATUS PUBLISHED 2' },
    @{ File = 'expected-not-queued.txt';    Exit = 0; Token = 'STATUS NOT QUEUED 4' },
    @{ File = 'unexpected-not-queued.txt';  Exit = 3; Token = 'UNEXPECTED_NOT_QUEUED' },
    @{ File = 'failure.txt';                Exit = 2; Token = 'STATUS FAILURE 1' },
    @{ File = 'publishing.txt';             Exit = 0; Token = 'STATUS PUBLISHING 2' },
    @{ File = 'empty.txt';                  Exit = 0; Token = 'OBJECT_ROWS 0' },
    @{ File = 'ablscale3-real-layout-not-queued.txt'; Exit = 3; Token = 'STATUS NOT QUEUED 11' },
    @{
        File = 'ablscale3-real-layout-not-queued.txt'
        Exit = 0
        Token = 'EXPECTED_NOT_QUEUED'
        ExpectedCsv = 'DM_INFO,DM_STAT_TABLE,DM_PROCESS_EVENT,DM_PROCESS,DM_PROCESS_QUEUE,HE_JOB,MP_GROUP_REFRESH_STATE'
    },
    @{
        File = 'real-layout-failure.txt'
        Exit = 2
        Token = 'STATUS FAILURE 1'
        ExpectedCsv = 'DM_INFO,DM_STAT_TABLE,DM_PROCESS_EVENT,DM_PROCESS,DM_PROCESS_QUEUE,HE_JOB,MP_GROUP_REFRESH_STATE'
    }
)

$failures = [System.Collections.Generic.List[string]]::new()
foreach ($case in $cases) {
    if ($case.ContainsKey('ExpectedCsv')) {
        $output = & ssh $Runner "bash '$remoteRoot/summarize-status.sh' '$remoteRoot/fixtures/$($case.File)' '$($case.ExpectedCsv)' 2>&1"
    } else {
        $output = & ssh $Runner "bash '$remoteRoot/summarize-status.sh' '$remoteRoot/fixtures/$($case.File)' 2>&1"
    }
    $actualExit = $LASTEXITCODE
    $text = $output -join "`n"

    if ($actualExit -ne $case.Exit) {
        $failures.Add("$($case.File): expected exit $($case.Exit), got $actualExit. Output: $text")
    }
    if ($text -notmatch [regex]::Escape($case.Token)) {
        $failures.Add("$($case.File): missing token '$($case.Token)'. Output: $text")
    }
}

if ($failures.Count -gt 0) {
    throw ($failures -join "`n")
}

Write-Output "$($cases.Count) parser fixture tests passed"
