[CmdletBinding()]
param(
    [ValidateSet('FPABL','ABLFHIR','FPSG')]
    [string]$DbEnv,

    [Parameter(Mandatory = $false)]
    [string]$ConnectionString,

    [Parameter(Mandatory = $false)]
    [string]$TnsName,

    [Parameter(Mandatory = $false)]
    [string]$UserName,

    [Parameter(Mandatory = $false)]
    [string]$Password,

    [Parameter(Mandatory = $false)]
    [string]$Query,

    [Parameter(Mandatory = $false)]
    [string]$QueryFile,

    [ValidateSet('table','csv','json')]
    [string]$OutputFormat = 'table',

    [Parameter(Mandatory = $false)]
    [string]$OutFile
)

$ErrorActionPreference = 'Stop'

$DbProfiles = @{
    FPABL = @{
        UserName = 'v500'
        Password = 'CERner##_123ORA'
        ConnectionString = '10.37.163.164:1521/sfpabl.world'
    }
    ABLFHIR = @{
        UserName = 'v500'
        Password = 'v500'
        ConnectionString = '10.191.200.24:1521/sfpabl.world'
    }
    FPSG = @{
        UserName = 'v500'
        Password = 'CERner##_123ORA'
        ConnectionString = '10.37.174.186:1521/sfpsg.world'
    }
}

function Resolve-SqlClient {
    $sqlplus = Get-Command sqlplus -ErrorAction SilentlyContinue
    if ($sqlplus) {
        return @{ Name = 'sqlplus'; Path = $sqlplus.Path }
    }

    $fallbackSqlplus = 'C:/Users/prakash/AppData/Local/Microsoft/WinGet/Packages/Oracle.InstantClient.Basic_Microsoft.Winget.Source_8wekyb3d8bbwe/instantclient_23_9/sqlplus.exe'
    if (Test-Path $fallbackSqlplus) {
        return @{ Name = 'sqlplus'; Path = $fallbackSqlplus }
    }

    $sql = Get-Command sql -ErrorAction SilentlyContinue
    if ($sql) {
        return @{ Name = 'sql'; Path = $sql.Path }
    }

    $fallbackSqlcl = 'C:/Users/prakash/AppData/Local/Microsoft/WinGet/Packages/Oracle.SQLcl_Microsoft.Winget.Source_8wekyb3d8bbwe/sqlcl/bin/sql.exe'
    if (Test-Path $fallbackSqlcl) {
        return @{ Name = 'sql'; Path = $fallbackSqlcl }
    }

    throw "Oracle client not found. Install Oracle Instant Client (sqlplus) or SQLcl (sql), then retry."
}

function Remove-SqlComments {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text
    )

    # Strip block comments first, then line comments.
    $withoutBlock = [regex]::Replace($Text, '(?s)/\*.*?\*/', '')
    return [regex]::Replace($withoutBlock, '(?m)--.*$', '')
}

function Test-SelectOnlySql {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Sql
    )

    $clean = (Remove-SqlComments -Text $Sql).Trim()
    if ([string]::IsNullOrWhiteSpace($clean)) {
        return $false
    }

    # Allow SELECT and WITH (CTE that resolves to SELECT).
    if ($clean -notmatch '^(?is)\s*(select|with)\b') {
        return $false
    }

    # Reject obvious non-read-only verbs anywhere in the text.
    $blocked = @(
        'insert','update','delete','merge',
        'alter','drop','truncate','create','rename','comment',
        'grant','revoke',
        'begin','declare',
        'commit','rollback',
        'execute','exec','call'
    )

    foreach ($verb in $blocked) {
        if ($clean -match ("(?i)\b{0}\b" -f [regex]::Escape($verb))) {
            return $false
        }
    }

    return $true
}

if ([string]::IsNullOrWhiteSpace($Query) -and [string]::IsNullOrWhiteSpace($QueryFile)) {
    throw "Provide either -Query or -QueryFile."
}

if (-not [string]::IsNullOrWhiteSpace($Query) -and -not [string]::IsNullOrWhiteSpace($QueryFile)) {
    throw "Provide only one of -Query or -QueryFile."
}

if (-not [string]::IsNullOrWhiteSpace($DbEnv)) {
    if (-not $DbProfiles.ContainsKey($DbEnv)) {
        throw "Unknown -DbEnv '$DbEnv'."
    }

    $profile = $DbProfiles[$DbEnv]

    if ([string]::IsNullOrWhiteSpace($UserName)) {
        $UserName = $profile.UserName
    }

    if ([string]::IsNullOrWhiteSpace($Password)) {
        $Password = $profile.Password
    }

    if ([string]::IsNullOrWhiteSpace($ConnectionString) -and [string]::IsNullOrWhiteSpace($TnsName)) {
        $ConnectionString = $profile.ConnectionString
    }
}

if ([string]::IsNullOrWhiteSpace($ConnectionString) -and [string]::IsNullOrWhiteSpace($TnsName)) {
    throw "Provide either -ConnectionString or -TnsName (or use -DbEnv)."
}

if (-not [string]::IsNullOrWhiteSpace($ConnectionString) -and -not [string]::IsNullOrWhiteSpace($TnsName)) {
    throw "Provide only one of -ConnectionString or -TnsName."
}

if ([string]::IsNullOrWhiteSpace($UserName)) {
    throw "UserName not provided. Use -UserName or -DbEnv."
}

if ([string]::IsNullOrWhiteSpace($Password)) {
    $Password = $env:ORACLE_DB_PASSWORD
}

if ([string]::IsNullOrWhiteSpace($Password)) {
    throw "Password not provided. Use -Password, ORACLE_DB_PASSWORD, or -DbEnv."
}

$target = if (-not [string]::IsNullOrWhiteSpace($ConnectionString)) { $ConnectionString } else { $TnsName }
$sqlText = if ($QueryFile) {
    Get-Content -Raw -Path $QueryFile
} else {
    # SQL*Plus script mode needs a statement terminator.
    $q = $Query.TrimEnd()
    if ($q -notmatch '(;|/)$') {
        $q = "$q;"
    }
    $q
}

if (-not (Test-SelectOnlySql -Sql $sqlText)) {
    throw "Query blocked by hard lock. Only read-only SELECT/CTE SQL is allowed."
}
$sqlClient = Resolve-SqlClient

$tempFile = Join-Path $env:TEMP ("oracle-query-" + [Guid]::NewGuid().ToString() + ".sql")
$stdoutFile = Join-Path $env:TEMP ("oracle-query-" + [Guid]::NewGuid().ToString() + ".stdout.txt")
$stderrFile = Join-Path $env:TEMP ("oracle-query-" + [Guid]::NewGuid().ToString() + ".stderr.txt")

try {
    $settings = @()

    switch ($OutputFormat) {
        'table' {
            $settings += "set pagesize 50000"
            $settings += "set linesize 32767"
            $settings += "set trimspool on"
            $settings += "set tab off"
            $settings += "set feedback on"
            $settings += "set heading on"
            $settings += "set colsep ' | '"
        }
        'csv' {
            $settings += "set markup csv on delimiter ',' quote on"
            $settings += "set feedback off"
            $settings += "set heading on"
        }
        'json' {
            $settings += "set pagesize 50000"
            $settings += "set linesize 32767"
            $settings += "set trimspool on"
            $settings += "set feedback off"
            $settings += "set heading off"
        }
    }

    $scriptBody = @(
        "whenever sqlerror exit sql.sqlcode",
        "set echo off",
        "set verify off"
    ) + $settings + @(
        $sqlText,
        "exit"
    )

    Set-Content -Path $tempFile -Value ($scriptBody -join [Environment]::NewLine) -Encoding ASCII

    $login = "{0}/{1}@{2}" -f $UserName, $Password, $target

    $exeEsc = '"' + $sqlClient.Path.Replace('"', '""') + '"'
    $scriptArg = '@"' + $tempFile.Replace('"', '""') + '"'
    $stdoutEsc = '"' + $stdoutFile.Replace('"', '""') + '"'
    $stderrEsc = '"' + $stderrFile.Replace('"', '""') + '"'
    $cmdLine = "$exeEsc -S $login $scriptArg 1> $stdoutEsc 2> $stderrEsc"
    & cmd /c $cmdLine
    $exitCode = $LASTEXITCODE
    $stdout = if (Test-Path $stdoutFile) { Get-Content -Raw -Path $stdoutFile } else { "" }
    $stderr = if (Test-Path $stderrFile) { Get-Content -Raw -Path $stderrFile } else { "" }
    $combined = @($stdout, $stderr) -join [Environment]::NewLine

    if ($exitCode -ne 0) {
        $joined = $combined.Trim()
        throw "Oracle query failed (exit $exitCode).`n$joined"
    }

    $text = $combined.Trim()

    if ($OutFile) {
        Set-Content -Path $OutFile -Value $text -Encoding UTF8
        Write-Output "Wrote output to: $OutFile"
    }

    Write-Output $text
}
finally {
    if (Test-Path $tempFile) {
        Remove-Item -Path $tempFile -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path $stdoutFile) {
        Remove-Item -Path $stdoutFile -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path $stderrFile) {
        Remove-Item -Path $stderrFile -Force -ErrorAction SilentlyContinue
    }
}



