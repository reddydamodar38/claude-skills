param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('start', 'status', 'stop')]
    [string]$Action
)

$ErrorActionPreference = 'Stop'

$target = 'opc@10.44.121.15'
$hostKey = 'SHA256:MFpjjwtRcQ80ky/fQUoLDozygKyMNNXpBOR90tdj+Pg'
$remoteRunner = '/ablpub/OCI/Torq/Gatling/.gatling-node-batch-runner.remote.sh'
$remoteScriptPath = Join-Path $PSScriptRoot 'gatling_node_batch_remote.sh'

function Resolve-PlinkPath {
    $testOverride = [Environment]::GetEnvironmentVariable('GATLING_NODE_BATCH_PLINK')
    if (-not [string]::IsNullOrWhiteSpace($testOverride)) {
        $testMode = [Environment]::GetEnvironmentVariable('GATLING_NODE_BATCH_TEST_MODE')
        if ($testMode -ne '1') {
            throw 'GATLING_NODE_BATCH_PLINK requires GATLING_NODE_BATCH_TEST_MODE=1.'
        }
        if (-not (Test-Path -LiteralPath $testOverride -PathType Leaf)) {
            throw "Test Plink launcher was not found: $testOverride"
        }
        return (Resolve-Path -LiteralPath $testOverride).Path
    }

    $command = Get-Command 'plink.exe' -CommandType Application -ErrorAction SilentlyContinue
    if ($null -ne $command) {
        $plinkPath = $command.Source
    }

    if ([string]::IsNullOrWhiteSpace($plinkPath)) {
        $installPaths = @(
            (Join-Path $env:ProgramFiles 'PuTTY\plink.exe'),
            (Join-Path ${env:ProgramFiles(x86)} 'PuTTY\plink.exe')
        )
        foreach ($path in $installPaths) {
            if (-not [string]::IsNullOrWhiteSpace($path) -and (Test-Path -LiteralPath $path -PathType Leaf)) {
                $plinkPath = $path
                break
            }
        }
    }

    if ([string]::IsNullOrWhiteSpace($plinkPath)) {
        throw 'plink.exe was not found on PATH or in a standard PuTTY install path.'
    }
    if (-not (Get-Process -Name 'pageant' -ErrorAction SilentlyContinue)) {
        throw 'Pageant is not running. Load the approved SSH key into Pageant first.'
    }
    return $plinkPath
}

$plink = Resolve-PlinkPath
$remoteScript = (Get-Content -LiteralPath $remoteScriptPath -Raw).TrimEnd("`r", "`n")
$plinkArguments = @('-batch', '-agent', '-hostkey', $hostKey, $target)

if ($Action -eq 'start') {
    $deployCommand = "sudo -n tee $remoteRunner >/dev/null && sudo -n chmod 700 $remoteRunner"
    $remoteScript | & $plink @plinkArguments $deployCommand
    $deployExitCode = $LASTEXITCODE
    if ($deployExitCode -ne 0) {
        exit $deployExitCode
    }

    & $plink @plinkArguments "bash $remoteRunner start"
    exit $LASTEXITCODE
}

$remoteScript | & $plink @plinkArguments "bash -s -- $Action"
exit $LASTEXITCODE
