param(
  [Parameter(Mandatory=$true)][string]$ScenarioName,
  [Parameter(Mandatory=$true)][string]$UsernameBase,
  [Parameter(Mandatory=$true)][string]$PersonLast,
  [ValidateSet("fpabl","ablfhir","fpabl-alt","fpabl2")][string]$DbEnv = "fpabl",
  [string]$UserSimpleQuery,
  [string]$PatientSimpleQuery,
  [switch]$SkipSqlplusValidation,
  [string]$TargetAlias = "ablfhir",
  [string]$HostName = "10.191.200.22",
  [string]$UserName = "root",
  [string]$KeyPath = "C:/Users/prakash/.ssh/id_gatling",
  [string]$LocalScriptRoot = "C:/Users/prakash/Desktop/project/NBS/gatling/script",
  [string]$RemoteBaseDir = "/root/gatling",
  [string]$RunnerScript = "C:/Users/prakash/.codex/skills/gatling-runner/scripts/run_gatling_remote.ps1",
  [switch]$SkipRunner
)

$ErrorActionPreference = "Stop"

if ($TargetAlias -ieq "ablfhir") {
  if (-not $PSBoundParameters.ContainsKey("HostName")) { $HostName = "10.191.200.22" }
  if (-not $PSBoundParameters.ContainsKey("UserName")) { $UserName = "root" }
  if (-not $PSBoundParameters.ContainsKey("KeyPath")) { $KeyPath = "C:/Users/prakash/.ssh/id_gatling" }
} else {
  throw "Unknown TargetAlias '$TargetAlias'. Supported aliases: ablfhir"
}

if (-not (Test-Path $KeyPath)) {
  throw "SSH key file not found: $KeyPath"
}

$scenarioDir = Join-Path $LocalScriptRoot $ScenarioName
$scenarioYamlPath = Join-Path $scenarioDir "scenario.yaml"
$scenarioDataPath = Join-Path $scenarioDir "scenario-data.yaml"
if (-not (Test-Path $scenarioYamlPath)) { throw "Missing file: $scenarioYamlPath" }
if (-not (Test-Path $scenarioDataPath)) { throw "Missing file: $scenarioDataPath" }

$dbMatrix = @{
  "fpabl" = @{
    User = "v500"
    Password = "CERner##_123ORA"
    Url = "10.37.163.164:1521/sfpabl.world"
  }
  "ablfhir" = @{
    User = "v500"
    Password = "v500"
    Url = "10.191.200.24:1521/sfpabl.world"
  }
  "fpabl-alt" = @{
    User = "v500"
    Password = "CERner##_123ORA"
    Url = "10.37.163.164:1521/sfpabl.world"
  }
  "fpabl2" = @{
    User = "v500"
    Password = "CERner##_123ORA"
    Url = "10.37.163.164:1521/sfpabl.world"
  }
}

$db = $dbMatrix[$DbEnv]
if ($null -eq $db) { throw "Unsupported DbEnv: $DbEnv" }

$sqlplusScript = "C:/Users/prakash/.codex/skills/sqlplus/scripts/run_oracle_query.ps1"

function Resolve-SqlplusDbEnv {
  param([string]$EnvName)
  switch ($EnvName.ToLowerInvariant()) {
    "ablfhir" { return "ABLFHIR" }
    "fpabl" { return "FPABL" }
    "fpabl-alt" { return "FPABL" }
    "fpabl2" { return "FPABL" }
    default { throw "No SQLPlus DbEnv mapping for '$EnvName'" }
  }
}

function Get-SqlInputMode {
  param(
    [string]$InputQuery,
    [string]$FallbackPredicate
  )

  if ([string]::IsNullOrWhiteSpace($InputQuery)) {
    return [pscustomobject]@{
      Mode = "predicate"
      Text = $FallbackPredicate
    }
  }

  $q = $InputQuery.Trim().TrimEnd(";")

  if ($q -match '(?is)\bselect\b.+\bfrom\b') {
    return [pscustomobject]@{
      Mode = "full"
      Text = $q
    }
  }

  $whereMatch = [regex]::Match($q, '(?is)\bwhere\b(?<pred>.+?)(\border\s+by\b|\bfetch\b|\boffset\b|$)')
  if ($whereMatch.Success) {
    $pred = $whereMatch.Groups["pred"].Value.Trim()
    if (-not [string]::IsNullOrWhiteSpace($pred)) {
      return [pscustomobject]@{
        Mode = "predicate"
        Text = $pred
      }
    }
  }

  return [pscustomobject]@{
    Mode = "predicate"
    Text = $q
  }
}

function Invoke-SqlplusPreview {
  param(
    [string]$DbEnvForSqlplus,
    [string]$Query,
    [string]$Label
  )

  if (-not (Test-Path $sqlplusScript)) {
    throw "sqlplus skill script not found: $sqlplusScript"
  }

  $preview = "SELECT * FROM (" + ($Query.Trim().TrimEnd(";")) + ") WHERE ROWNUM <= 5"
  Write-Host "[sqlplus] Previewing $Label query on $DbEnvForSqlplus"
  & pwsh -NoProfile -File $sqlplusScript -DbEnv $DbEnvForSqlplus -Query $preview -OutputFormat table
  if ($LASTEXITCODE -ne 0) {
    throw "SQLPlus preview failed for $Label query."
  }
}

function Invoke-External {
  param(
    [string]$Exe,
    [string[]]$CmdArgs
  )
  $cmdText = "$Exe $($CmdArgs -join ' ')"
  $startTs = Get-Date
  Write-Host "[$($startTs.ToString('HH:mm:ss'))] RUN: $cmdText"
  & $Exe @CmdArgs 2>&1 | ForEach-Object {
    if ($null -eq $_) { return }
    $text = [string]$_
    if ([string]::IsNullOrWhiteSpace($text)) { return }
    Write-Host "[$((Get-Date).ToString('HH:mm:ss'))] $text"
  }
  $exitCode = $LASTEXITCODE
  $elapsed = [int]((Get-Date) - $startTs).TotalSeconds
  Write-Host "[$((Get-Date).ToString('HH:mm:ss'))] DONE (exit=$exitCode, ${elapsed}s): $Exe"
  if ($exitCode -ne 0) {
    throw "Command failed ($exitCode): $cmdText"
  }
}

function Invoke-Ssh {
  param([string]$RemoteCommand)
  $sshArgs = @(
    "-o", "BatchMode=yes",
    "-o", "ConnectTimeout=15",
    "-o", "StrictHostKeyChecking=no",
    "-o", "UserKnownHostsFile=/dev/null",
    "-i", $KeyPath,
    "$UserName@$HostName",
    $RemoteCommand
  )
  Invoke-External -Exe "ssh" -CmdArgs $sshArgs
}

function Get-SshOutput {
  param([string]$RemoteCommand)
  $sshArgs = @(
    "-q",
    "-o", "BatchMode=yes",
    "-o", "ConnectTimeout=15",
    "-o", "StrictHostKeyChecking=no",
    "-o", "UserKnownHostsFile=/dev/null",
    "-i", $KeyPath,
    "$UserName@$HostName",
    $RemoteCommand
  )
  $stdout = New-Object System.Collections.Generic.List[string]
  & ssh @sshArgs 2>&1 | ForEach-Object {
    if ($null -eq $_) { return }
    $text = [string]$_
    if ([string]::IsNullOrWhiteSpace($text)) { return }
    Write-Host "[$((Get-Date).ToString('HH:mm:ss'))] $text"
    if ($_ -is [System.Management.Automation.ErrorRecord]) { return }
    if ($text -like 'Warning:*') { return }
    $stdout.Add($text) | Out-Null
  }
  if ($LASTEXITCODE -ne 0) {
    throw "ssh capture failed: $RemoteCommand"
  }
  return (($stdout.ToArray()) -join "`n").Trim()
}

function Invoke-ScpUploadFile {
  param([string]$LocalFile, [string]$RemoteTargetFile)
  $scpArgs = @(
    "-o", "BatchMode=yes",
    "-o", "ConnectTimeout=15",
    "-o", "StrictHostKeyChecking=no",
    "-o", "UserKnownHostsFile=/dev/null",
    "-i", $KeyPath,
    ($LocalFile -replace "\\","/"),
    "${UserName}@${HostName}:$RemoteTargetFile"
  )
  Invoke-External -Exe "scp" -CmdArgs $scpArgs
}

function Invoke-ScpDownloadFile {
  param([string]$RemoteFile, [string]$LocalFile)
  $scpArgs = @(
    "-o", "BatchMode=yes",
    "-o", "ConnectTimeout=15",
    "-o", "StrictHostKeyChecking=no",
    "-o", "UserKnownHostsFile=/dev/null",
    "-i", $KeyPath,
    "${UserName}@${HostName}:$RemoteFile",
    ($LocalFile -replace "\\","/")
  )
  Invoke-External -Exe "scp" -CmdArgs $scpArgs
}

function Escape-YamlDoubleQuoted {
  param([string]$Value)
  if ($null -eq $Value) { return "" }
  return (($Value -replace '\\', '\\\\') -replace '"', '\"')
}

function Normalize-DatePlaceholderQuotes {
  param([string]$Value)
  if ($null -eq $Value) { return "" }
  $text = [string]$Value
  # Normalize quoted date placeholders from generator output:
  # "'{currentDate 15 Day}'" -> "{currentDate 15 Day}"
  if ($text -match "^'\{currentDate[^}]*\}'$") {
    return $text.Substring(1, $text.Length - 2)
  }
  return $text
}

function Get-MapKeyCaseInsensitive {
  param(
    [System.Collections.IDictionary]$Map,
    [string]$LogicalKey
  )
  if ($null -eq $Map -or [string]::IsNullOrWhiteSpace($LogicalKey)) { return $null }
  foreach ($k in $Map.Keys) {
    if ($null -eq $k) { continue }
    if ($k.ToString().ToLowerInvariant() -eq $LogicalKey.ToLowerInvariant()) {
      return [string]$k
    }
  }
  return $null
}

function Get-MapValueCaseInsensitive {
  param(
    [System.Collections.IDictionary]$Map,
    [string]$LogicalKey
  )
  $actualKey = Get-MapKeyCaseInsensitive -Map $Map -LogicalKey $LogicalKey
  if ($null -eq $actualKey) { return $null }
  return [string]$Map[$actualKey]
}

function Replace-BytePatternInPlace {
  param(
    [byte[]]$Buffer,
    [byte[]]$OldPattern,
    [byte[]]$NewPattern
  )
  if ($null -eq $Buffer -or $null -eq $OldPattern -or $null -eq $NewPattern) { return 0 }
  if ($OldPattern.Length -eq 0 -or $OldPattern.Length -ne $NewPattern.Length) { return 0 }
  if ($Buffer.Length -lt $OldPattern.Length) { return 0 }

  $replaceCount = 0
  for ($i = 0; $i -le ($Buffer.Length - $OldPattern.Length); $i++) {
    $matched = $true
    for ($j = 0; $j -lt $OldPattern.Length; $j++) {
      if ($Buffer[$i + $j] -ne $OldPattern[$j]) {
        $matched = $false
        break
      }
    }
    if (-not $matched) { continue }
    for ($j = 0; $j -lt $NewPattern.Length; $j++) {
      $Buffer[$i + $j] = $NewPattern[$j]
    }
    $replaceCount++
    $i += ($OldPattern.Length - 1)
  }
  return $replaceCount
}

function Find-PatternOffsets {
  param(
    [byte[]]$Buffer,
    [byte[]]$Pattern
  )
  $hits = New-Object System.Collections.Generic.List[int]
  if ($null -eq $Buffer -or $null -eq $Pattern) { return $hits }
  if ($Pattern.Length -eq 0 -or $Buffer.Length -lt $Pattern.Length) { return $hits }
  for ($i = 0; $i -le ($Buffer.Length - $Pattern.Length); $i++) {
    $matched = $true
    for ($j = 0; $j -lt $Pattern.Length; $j++) {
      if ($Buffer[$i + $j] -ne $Pattern[$j]) {
        $matched = $false
        break
      }
    }
    if ($matched) {
      $hits.Add($i) | Out-Null
      $i += ($Pattern.Length - 1)
    }
  }
  return $hits
}

function Update-AppInfoUpdtIdPreserveBytes {
  param(
    [string]$AppInfoBase64,
    [string]$OldUserId,
    [string]$NewUserId
  )

  if ([string]::IsNullOrWhiteSpace($AppInfoBase64)) { return $AppInfoBase64 }
  if ([string]::IsNullOrWhiteSpace($OldUserId) -or [string]::IsNullOrWhiteSpace($NewUserId)) { return $AppInfoBase64 }
  if ($OldUserId -eq $NewUserId) { return $AppInfoBase64 }
  if ($OldUserId.Length -ne $NewUserId.Length) {
    Write-Warning "Skipping appinfo UPDT_ID byte-preserving update because old/new user_id lengths differ ($OldUserId -> $NewUserId)."
    return $AppInfoBase64
  }

  try {
    $rawBytes = [Convert]::FromBase64String($AppInfoBase64)
  } catch {
    Write-Warning "Skipping appinfo update because value is not valid base64."
    return $AppInfoBase64
  }

  # appinfo payload is base64-encoded binary metadata; update only UPDT_ID value bytes.
  $keyBytes = [System.Text.Encoding]::ASCII.GetBytes("UPDT_ID")
  $oldAscii = [System.Text.Encoding]::ASCII.GetBytes($OldUserId)
  $newAscii = [System.Text.Encoding]::ASCII.GetBytes($NewUserId)

  $keyHits = Find-PatternOffsets -Buffer $rawBytes -Pattern $keyBytes
  if ($keyHits.Count -eq 0) {
    Write-Warning "appinfo does not contain UPDT_ID key marker; keeping original appinfo unchanged."
    return $AppInfoBase64
  }

  $idHits = Find-PatternOffsets -Buffer $rawBytes -Pattern $oldAscii
  if ($idHits.Count -eq 0) {
    Write-Warning "No matching UPDT_ID byte pattern found inside appinfo; keeping original appinfo bytes unchanged."
    return $AppInfoBase64
  }

  # Prefer the first user-id occurrence after the UPDT_ID key declaration area.
  $replaceAt = -1
  $lastKeyPos = $keyHits[$keyHits.Count - 1]
  foreach ($hit in $idHits) {
    if ($hit -gt $lastKeyPos) {
      $replaceAt = $hit
      break
    }
  }
  if ($replaceAt -lt 0) {
    $replaceAt = $idHits[0]
  }

  for ($i = 0; $i -lt $newAscii.Length; $i++) {
    $rawBytes[$replaceAt + $i] = $newAscii[$i]
  }

  return [Convert]::ToBase64String($rawBytes)
}

function Get-ScenarioTransactionName {
  param([string]$Path, [string]$FallbackScenarioName)
  $raw = Get-Content -Raw $Path
  $m = [regex]::Match($raw, '(?m)^\s*name\s*:\s*"?([^"\r\n]+)"?\s*$')
  if ($m.Success) {
    return $m.Groups[1].Value.Trim()
  }
  return (($FallbackScenarioName -replace '[^A-Za-z0-9]+','_').ToUpperInvariant())
}

function Get-GlobalParamsMap {
  param([string]$RawYaml)
  $map = [ordered]@{}
  $mBlock = [regex]::Match($RawYaml, '(?ms)^globalDataSets:.*?(?=^scenarioDataSets:|\z)')
  if (-not $mBlock.Success) { return $map }
  $block = $mBlock.Value
  $pairPattern = '(?ms)-\s+name:\s*"?(?<name>[^"\r\n]+)"?\s*\r?\n\s+value:\s*"?(?<value>[^"\r\n]*)"?'
  $matches = [regex]::Matches($block, $pairPattern)
  foreach ($m in $matches) {
    $name = $m.Groups["name"].Value.Trim()
    $value = $m.Groups["value"].Value
    if ([string]::IsNullOrWhiteSpace($name)) { continue }
    if (-not $map.Contains($name)) {
      $map[$name] = $value
    }
  }
  return $map
}

function Get-GlobalDataSets {
  param([string]$RawYaml)

  $sets = New-Object System.Collections.Generic.List[object]
  $mBlock = [regex]::Match($RawYaml, '(?ms)^globalDataSets:.*?(?=^scenarioDataSets:|\z)')
  if (-not $mBlock.Success) { return $sets }

  $lines = $mBlock.Value -split "`r?`n"
  $current = $null
  $pendingName = $null
  $inParams = $false

  function Add-CurrentSet {
    param([object]$SetObj, [System.Collections.Generic.List[object]]$Target)
    if ($null -ne $SetObj -and $null -ne $SetObj.Params -and $SetObj.Params.Count -gt 0) {
      $Target.Add($SetObj) | Out-Null
    }
  }

  foreach ($line in $lines) {
    $queryMatch = [regex]::Match($line, '^\s*-\s+queryString:\s*(?<q>.*)\s*$')
    if ($queryMatch.Success) {
      Add-CurrentSet -SetObj $current -Target $sets
      $q = $queryMatch.Groups["q"].Value.Trim()
      if ($q.StartsWith('"') -and $q.EndsWith('"') -and $q.Length -ge 2) {
        $q = $q.Substring(1, $q.Length - 2)
      }
      $current = [pscustomobject]@{
        QueryString = $q
        Params = [ordered]@{}
      }
      $pendingName = $null
      $inParams = $false
      continue
    }

    if ($null -eq $current) { continue }

    if ($line -match '^\s+params:\s*$') {
      $inParams = $true
      continue
    }

    if ($line -match '^\s+headers:\s*') {
      $inParams = $false
      $pendingName = $null
      continue
    }

    if (-not $inParams) { continue }

    $nameMatch = [regex]::Match($line, '^\s+-\s+name:\s*"?(?<name>[^"\r\n]+)"?\s*$')
    if ($nameMatch.Success) {
      $pendingName = $nameMatch.Groups["name"].Value.Trim()
      continue
    }

    $valueMatch = [regex]::Match($line, '^\s+value:\s*"?(?<value>[^"\r\n]*)"?\s*$')
    if ($null -ne $pendingName -and $valueMatch.Success) {
      $current.Params[$pendingName] = $valueMatch.Groups["value"].Value
      $pendingName = $null
      continue
    }
  }

  Add-CurrentSet -SetObj $current -Target $sets
  return $sets
}

function Get-SelectExpressionsFromGlobals {
  param(
    [System.Collections.IDictionary]$ExistingGlobals,
    [System.Collections.IDictionary]$ExpressionMap,
    [string[]]$DefaultKeys,
    [string]$Label
  )

  $selectedKeys = New-Object System.Collections.Generic.List[string]
  if ($null -ne $ExistingGlobals) {
    foreach ($k in $ExistingGlobals.Keys) {
      $lk = $k.ToLowerInvariant()
      if ($ExpressionMap.Contains($lk) -and -not $selectedKeys.Contains($lk)) {
        $selectedKeys.Add($lk)
      }
    }
  }

  if ($selectedKeys.Count -eq 0) {
    foreach ($dk in $DefaultKeys) {
      if ($ExpressionMap.Contains($dk) -and -not $selectedKeys.Contains($dk)) {
        $selectedKeys.Add($dk)
      }
    }
    Write-Host "No matching $Label columns found in existing globalDataSets. Using default framed columns: $($selectedKeys -join ', ')"
  } else {
    Write-Host "Using existing globalDataSets-driven $Label columns: $($selectedKeys -join ', ')"
  }

  $selectExprs = New-Object System.Collections.Generic.List[string]
  foreach ($sk in $selectedKeys) {
    $selectExprs.Add([string]$ExpressionMap[$sk])
  }
  return $selectExprs
}

function Build-FramedUserSql {
  param(
    [string]$Predicate,
    [string]$Authority,
    [System.Collections.IDictionary]$ExistingGlobals
  )

  $exprMap = [ordered]@{
    "authority"                    = "'$Authority' AS authority"
    "username"                     = "username"
    "user_id"                      = "PERSON_ID AS user_id"
    "prsnl_id"                     = "PERSON_ID AS prsnl_id"
    "password"                     = "'scale' AS password"
    "current_dt_tm"                = "'{currentDateTime}' AS current_dt_tm"
    "current_dt_tm_pastnineyears"  = "'{currentDateTime -3285 Day}' AS current_dt_tm_PastNineYears"
  }
  $defaults = @("authority","username","user_id","prsnl_id","password","current_dt_tm","current_dt_tm_pastnineyears")
  $selectExprs = Get-SelectExpressionsFromGlobals -ExistingGlobals $ExistingGlobals -ExpressionMap $exprMap -DefaultKeys $defaults -Label "user.sql"

  return "SELECT $($selectExprs -join ', ') FROM prsnl WHERE $Predicate ORDER BY PERSON_ID"
}

function Build-FramedPatientSql {
  param(
    [string]$Predicate,
    [System.Collections.IDictionary]$ExistingGlobals
  )

  $exprMap = [ordered]@{
    "fin_num"        = "ea.ALIAS AS fin_num"
    "person_id"      = "p.PERSON_ID AS person_id"
    "encntr_id"      = "o.ENCNTR_ID AS encntr_id"
    "order_id"       = "o.ORDER_ID AS order_id"
    "accession_nbr"  = "a.ACCESSION AS accession_nbr"
  }
  $defaults = @("fin_num","person_id","encntr_id","order_id","accession_nbr")
  $selectExprs = Get-SelectExpressionsFromGlobals -ExistingGlobals $ExistingGlobals -ExpressionMap $exprMap -DefaultKeys $defaults -Label "patient.sql"

  return "SELECT $($selectExprs -join ', ') FROM person p JOIN orders o ON p.PERSON_ID = o.PERSON_ID LEFT JOIN encounter e ON o.ENCNTR_ID = e.ENCNTR_ID LEFT JOIN encntr_alias ea ON e.ENCNTR_ID = ea.ENCNTR_ID AND ea.ENCNTR_ALIAS_TYPE_CD IN (1077) JOIN accession_order_r aor ON aor.order_id = o.order_id JOIN accession a ON a.ACCESSION_ID = aor.ACCESSION_ID WHERE $Predicate ORDER BY p.PERSON_ID, o.ORDER_ID"
}

function Build-GlobalBlock {
  param([System.Collections.IDictionary]$Params)
  $lines = New-Object System.Collections.Generic.List[string]
  $lines.Add("globalDataSets:")
  $lines.Add('- queryString: ""')
  $lines.Add("  params:")
  foreach ($k in $Params.Keys) {
    $v = Normalize-DatePlaceholderQuotes -Value ([string]$Params[$k])
    $lines.Add('  - name: "' + (Escape-YamlDoubleQuoted $k) + '"')
    $lines.Add('    value: "' + (Escape-YamlDoubleQuoted $v) + '"')
  }
  $lines.Add("  headers: null")
  return (($lines -join "`r`n") + "`r`n")
}

function Build-GlobalBlockFromDataSets {
  param([System.Collections.Generic.List[object]]$DataSets)
  $lines = New-Object System.Collections.Generic.List[string]
  $lines.Add("globalDataSets:")
  foreach ($ds in $DataSets) {
    if ($null -eq $ds) { continue }
    $paramsMap = $ds.Params
    if ($null -eq $paramsMap) { continue }
    $queryString = [string]$ds.QueryString
    if ([string]::IsNullOrWhiteSpace($queryString)) { $queryString = "" }
    $lines.Add('- queryString: "' + (Escape-YamlDoubleQuoted $queryString) + '"')
    $lines.Add("  params:")
    foreach ($k in @($paramsMap.Keys)) {
      if ($null -eq $k) { continue }
      $v = Normalize-DatePlaceholderQuotes -Value ([string]$paramsMap[$k])
      $lines.Add('  - name: "' + (Escape-YamlDoubleQuoted $k) + '"')
      $lines.Add('    value: "' + (Escape-YamlDoubleQuoted $v) + '"')
    }
    $lines.Add("  headers: null")
  }
  return (($lines -join "`r`n") + "`r`n")
}

$scenarioDataRaw = Get-Content -Raw $scenarioDataPath
$existingGlobalMapForSqlFraming = Get-GlobalParamsMap -RawYaml $scenarioDataRaw
$transactionName = Get-ScenarioTransactionName -Path $scenarioYamlPath -FallbackScenarioName $ScenarioName

$tmpRoot = Join-Path $env:TEMP ("gatling-scenario-data-creator-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tmpRoot -Force | Out-Null

$remoteTemp = "$RemoteBaseDir/gatling-scenario-data-creator-" + [guid]::NewGuid().ToString("N").Substring(0, 10)
$remoteOutFile = "$remoteTemp/scenario-data.yaml"
$localGeneratedScenarioData = Join-Path $tmpRoot "scenario-data.generated.yaml"
$userSqlPath = Join-Path $tmpRoot "user.sql"
$patientSqlPath = Join-Path $tmpRoot "patient.sql"
$framedSqlDir = Join-Path $scenarioDir "sql"

try {
  $defaultUserPredicate = "username LIKE UPPER('$UsernameBase%')"
  $defaultPatientPredicate = "p.NAME_LAST LIKE '$PersonLast%'"
  $userSqlInput = Get-SqlInputMode -InputQuery $UserSimpleQuery -FallbackPredicate $defaultUserPredicate
  $patientSqlInput = Get-SqlInputMode -InputQuery $PatientSimpleQuery -FallbackPredicate $defaultPatientPredicate

  New-Item -ItemType Directory -Path $framedSqlDir -Force | Out-Null

  if ($userSqlInput.Mode -eq "full") {
    $userSqlText = $userSqlInput.Text
  } else {
    # Keep one-line SQL so the remote generator parser can consume it safely.
    $userSqlText = Build-FramedUserSql -Predicate $userSqlInput.Text -Authority $TargetAlias -ExistingGlobals $existingGlobalMapForSqlFraming
  }

  if ($patientSqlInput.Mode -eq "full") {
    $patientSqlText = $patientSqlInput.Text
  } else {
    # Keep one-line SQL so the remote generator parser can consume it safely.
    $patientSqlText = Build-FramedPatientSql -Predicate $patientSqlInput.Text -ExistingGlobals $existingGlobalMapForSqlFraming
  }

  Set-Content -Path $userSqlPath -Value $userSqlText -Encoding UTF8
  Set-Content -Path $patientSqlPath -Value $patientSqlText -Encoding UTF8

  Write-Host "----- user.sql (effective query) -----"
  Write-Host $userSqlText
  Write-Host "----- patient.sql (effective query) -----"
  Write-Host $patientSqlText

  Copy-Item -Path $userSqlPath -Destination (Join-Path $framedSqlDir "user.sql") -Force
  Copy-Item -Path $patientSqlPath -Destination (Join-Path $framedSqlDir "patient.sql") -Force
  Write-Host "Framed SQL files saved at: $framedSqlDir"

  if (-not $SkipSqlplusValidation) {
    $sqlplusDbEnv = Resolve-SqlplusDbEnv -EnvName $DbEnv
    Invoke-SqlplusPreview -DbEnvForSqlplus $sqlplusDbEnv -Query (Get-Content -Raw $userSqlPath) -Label "user.sql"
    Invoke-SqlplusPreview -DbEnvForSqlplus $sqlplusDbEnv -Query (Get-Content -Raw $patientSqlPath) -Label "patient.sql"
  }

  Invoke-Ssh "set -e; rm -rf '$remoteTemp'; mkdir -p '$remoteTemp'"
  Invoke-ScpUploadFile -LocalFile $userSqlPath -RemoteTargetFile "$remoteTemp/user.sql"
  Invoke-ScpUploadFile -LocalFile $patientSqlPath -RemoteTargetFile "$remoteTemp/patient.sql"

  $jarCmd = @(
    "cd '$remoteTemp'",
    "java -jar '$RemoteBaseDir/scenario-data-generator.jar' -type SQL -dbusername '$($db.User)' -dbpassword '$($db.Password)' -dburl '$($db.Url)' -transactionname '$transactionName' -patientsql patient.sql -usersql user.sql -outputfilepath ."
  ) -join "; "
  Invoke-Ssh $jarCmd

  Invoke-ScpDownloadFile -RemoteFile $remoteOutFile -LocalFile $localGeneratedScenarioData
  $newRaw = Get-Content -Raw $localGeneratedScenarioData
  $oldRaw = Get-Content -Raw $scenarioDataPath

  $oldGlobalMatch = [regex]::Match($oldRaw, '(?ms)^globalDataSets:.*?(?=^scenarioDataSets:|\z)')
  $newGlobalMatch = [regex]::Match($newRaw, '(?ms)^globalDataSets:.*?(?=^scenarioDataSets:|\z)')
  if (-not $newGlobalMatch.Success) {
    throw "Generated scenario-data.yaml does not contain globalDataSets block."
  }

  $oldSets = Get-GlobalDataSets -RawYaml $oldRaw
  $newSets = Get-GlobalDataSets -RawYaml $newRaw

  $finalSets = New-Object System.Collections.Generic.List[object]

  if ($oldSets.Count -gt 0) {
    $oldDefaultParams = $oldSets[0].Params
    if ($null -eq $oldDefaultParams) { $oldDefaultParams = [ordered]@{} }
    $allowedKeys = @($oldDefaultParams.Keys)

    if ($newSets.Count -eq 0) {
      Write-Host "No generated globalDataSets rows found; keeping existing globalDataSets."
      foreach ($s in $oldSets) { $finalSets.Add($s) | Out-Null }
    } else {
      if ($allowedKeys.Count -eq 0) {
        Write-Host "Existing globalDataSets has no param keys; using generated key set as fallback."
        $firstNewParams = $newSets[0].Params
        if ($null -ne $firstNewParams) {
          $allowedKeys = @($firstNewParams.Keys)
        }
      }
      for ($newSetIdx = 0; $newSetIdx -lt $newSets.Count; $newSetIdx++) {
        $newSet = $newSets[$newSetIdx]
        $mergedParams = [ordered]@{}
        $newSetParams = $newSet.Params
        if ($null -eq $newSetParams) { $newSetParams = [ordered]@{} }
        foreach ($allowedKey in $allowedKeys) {
          if ($null -eq $allowedKey) { continue }
          $sourceKey = $null
          foreach ($candidateKey in $newSetParams.Keys) {
            if ($null -eq $candidateKey) { continue }
            if ($candidateKey.ToLowerInvariant() -eq $allowedKey.ToLowerInvariant()) {
              $sourceKey = $candidateKey
              break
            }
          }
          if ($null -ne $sourceKey) {
            $mergedParams[$allowedKey] = [string]$newSetParams[$sourceKey]
          } elseif ($null -ne $oldDefaultParams -and $oldDefaultParams.Contains($allowedKey)) {
            $mergedParams[$allowedKey] = [string]$oldDefaultParams[$allowedKey]
          } else {
            $mergedParams[$allowedKey] = ""
          }
        }

        foreach ($k in @($mergedParams.Keys)) {
          $lk = $k.ToLowerInvariant()
          if ($lk -eq "authority") { $mergedParams[$k] = "ablfhir" }
          elseif ($lk -eq "password") { $mergedParams[$k] = "scale" }
          elseif ($lk -eq "current_dt_tm") { $mergedParams[$k] = "{currentDateTime}" }
        }

        # If appinfo already exists in current scenario-data, update only the embedded UPDT_ID bytes.
        $appInfoKey = Get-MapKeyCaseInsensitive -Map $mergedParams -LogicalKey "appinfo"
        if ($null -ne $appInfoKey) {
          $oldRowParams = $null
          if ($newSetIdx -lt $oldSets.Count -and $null -ne $oldSets[$newSetIdx]) {
            $oldRowParams = $oldSets[$newSetIdx].Params
          }
          if ($null -eq $oldRowParams) {
            $oldRowParams = $oldDefaultParams
          }

          $oldAppInfoValue = Get-MapValueCaseInsensitive -Map $oldRowParams -LogicalKey "appinfo"
          if (-not [string]::IsNullOrWhiteSpace($oldAppInfoValue)) {
            $oldUserIdForAppInfo = Get-MapValueCaseInsensitive -Map $oldRowParams -LogicalKey "user_id"
            if ([string]::IsNullOrWhiteSpace($oldUserIdForAppInfo)) {
              $oldUserIdForAppInfo = Get-MapValueCaseInsensitive -Map $oldDefaultParams -LogicalKey "user_id"
            }
            $newUserIdForAppInfo = Get-MapValueCaseInsensitive -Map $mergedParams -LogicalKey "user_id"
            if (-not [string]::IsNullOrWhiteSpace($newUserIdForAppInfo)) {
              $mergedParams[$appInfoKey] = Update-AppInfoUpdtIdPreserveBytes -AppInfoBase64 $oldAppInfoValue -OldUserId $oldUserIdForAppInfo -NewUserId $newUserIdForAppInfo
            } else {
              $mergedParams[$appInfoKey] = $oldAppInfoValue
            }
          }
        }

        $finalSets.Add([pscustomobject]@{
          QueryString = ""
          Params = $mergedParams
        }) | Out-Null
      }
    }
  } elseif ($newSets.Count -gt 0) {
    Write-Host "No existing globalDataSets params found; using generated globalDataSets rows."
    foreach ($s in $newSets) { $finalSets.Add($s) | Out-Null }
  } else {
    throw "Neither existing nor generated globalDataSets rows were available to build output."
  }

  if ($finalSets.Count -eq 0) {
    throw "No usable globalDataSets rows were built."
  }

  $newGlobalBlock = Build-GlobalBlockFromDataSets -DataSets $finalSets
  if ($oldGlobalMatch.Success) {
    $patched = [regex]::Replace($oldRaw, '(?ms)^globalDataSets:.*?(?=^scenarioDataSets:|\z)', $newGlobalBlock)
  } elseif ($oldRaw -match '(?m)^scenarioDataSets:') {
    $patched = [regex]::Replace($oldRaw, '(?m)^scenarioDataSets:', $newGlobalBlock + "scenarioDataSets:")
  } else {
    $patched = $oldRaw.TrimEnd() + "`r`n" + $newGlobalBlock + "`r`nscenarioDataSets: null`r`n"
  }

  $backupStamp = Get-Date -Format "yyyyMMdd-HHmmss"
  $backupPath = Join-Path $scenarioDir ("scenario-data.yaml.sdc." + $backupStamp + ".bak")
  Copy-Item -Path $scenarioDataPath -Destination $backupPath -Force
  Write-Host "Backed up existing scenario-data.yaml to: $backupPath"

  Set-Content -Path $scenarioDataPath -Value $patched -Encoding UTF8
  Write-Host "Updated scenario-data globalDataSets at: $scenarioDataPath"
}
finally {
  try { Invoke-Ssh "rm -rf '$remoteTemp'" } catch {}
  if (Test-Path $tmpRoot) {
    Remove-Item -Path $tmpRoot -Recurse -Force -ErrorAction SilentlyContinue
  }
}

if (-not $SkipRunner) {
  if (-not (Test-Path $RunnerScript)) {
    throw "gatling-runner script not found: $RunnerScript"
  }
  & pwsh -NoProfile -File $RunnerScript -ScenarioName $ScenarioName -TargetAlias $TargetAlias
  if ($LASTEXITCODE -ne 0) {
    throw "gatling-runner failed for scenario: $ScenarioName"
  }
}

Write-Host "Completed."

