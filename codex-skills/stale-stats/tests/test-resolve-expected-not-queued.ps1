[CmdletBinding()]
param(
    [string]$Runner = 'root@dh2vpc067.dh2.cerner.com'
)

$ErrorActionPreference = 'Stop'

$skillRoot = Split-Path -Parent $PSScriptRoot
$resolver = Join-Path $skillRoot 'scripts\resolve-expected-not-queued.py'
$policy = Join-Path $skillRoot 'vars\expected-not-queued.json'
$remoteRoot = '/root/codex-workspace/stale-stats-policy-tests'

if (-not (Test-Path -LiteralPath $resolver)) {
    throw "Resolver is missing: $resolver"
}
if (-not (Test-Path -LiteralPath $policy)) {
    throw "Policy is missing: $policy"
}

$identity = & ssh $Runner 'hostname; id -un; pwd'
if ($LASTEXITCODE -ne 0) {
    throw "Unable to connect to Linux runner '$Runner'."
}
if (($identity -join "`n") -notmatch '(?m)^dh2vpc067(?:\.dh2\.cerner\.com)?$' -or
    ($identity -join "`n") -notmatch '(?m)^root$') {
    throw "Unexpected Linux runner identity: $($identity -join ', ')"
}

& ssh $Runner "mkdir -p '$remoteRoot/scripts' '$remoteRoot/vars'"
if ($LASTEXITCODE -ne 0) {
    throw 'Unable to create the remote policy-test directory.'
}

& scp $resolver "${Runner}:$remoteRoot/scripts/resolve-expected-not-queued.py"
if ($LASTEXITCODE -ne 0) {
    throw 'Unable to copy the resolver to the Linux runner.'
}
& scp $policy "${Runner}:$remoteRoot/vars/expected-not-queued.json"
if ($LASTEXITCODE -ne 0) {
    throw 'Unable to copy the policy to the Linux runner.'
}

$cases = @(
    @{
        Domain = 'ablscale3'
        Exit = 0
        Output = 'DM_INFO,DM_STAT_TABLE,DM_PROCESS_EVENT,DM_PROCESS,DM_PROCESS_QUEUE,HE_JOB,MP_GROUP_REFRESH_STATE'
    },
    @{
        Domain = 'another-domain'
        Exit = 0
        Output = 'DM_INFO,DM_STAT_TABLE,DM_PROCESS_EVENT,DM_PROCESS'
    },
    @{
        Domain = 'invalid/domain'
        Exit = 64
        Output = 'Unsafe domain'
    }
)

$failures = [System.Collections.Generic.List[string]]::new()
foreach ($case in $cases) {
    $output = & ssh $Runner "python3 '$remoteRoot/scripts/resolve-expected-not-queued.py' '$($case.Domain)' 2>&1"
    $actualExit = $LASTEXITCODE
    $text = $output -join "`n"

    if ($actualExit -ne $case.Exit) {
        $failures.Add("$($case.Domain): expected exit $($case.Exit), got $actualExit. Output: $text")
    }
    if ($text -ne $case.Output) {
        $failures.Add("$($case.Domain): expected '$($case.Output)', got '$text'.")
    }
}

if ($failures.Count -gt 0) {
    throw ($failures -join "`n")
}

Write-Output "$($cases.Count) policy resolution tests passed"
