param(
  [string]$HostName = "10.191.200.22",
  [string]$UserName = "root",
  [string]$KeyPath = "C:/Users/prakash/.ssh/id_gatling",
  [string]$TargetAlias = "ablfhir",
  [ValidateSet("FPABL","ABLFHIR","FPSG")]
  [string]$DbEnv = "ABLFHIR",
  [string[]]$RecordingNames = @(),
  [string]$RecordingsRoot = "C:/Users/prakash/Desktop/project/NBS/gatling/recordings",
  [string]$DoneScriptsRoot = "C:/Users/prakash/Desktop/project/NBS/gatling/script/done",
  [string]$GeneratedScriptsRoot = "C:/Users/prakash/Desktop/project/NBS/gatling/script/generated",
  [string]$RunnerScriptsRoot = "C:/Users/prakash/.codex/skills/gatling-runner/scripts",
  [string]$ConversionReportsRoot = "C:/Users/prakash/Desktop/project/NBS/gatling/reports/conversion-yaml-audit",
  [string]$SqlplusScriptPath = "C:/Users/prakash/.codex/skills/sqlplus/scripts/run_oracle_query.ps1",
  [string]$SqlFile = "C:/Users/prakash/Desktop/project/NBS/scenario-data/ALL_SCRIPTS_SQL.sql",
  [string]$TimeZone = "America/Chicago",
  [string]$ProvidedMoveToGlobal = "",
  [string]$Pass2PriorityMoveToGlobal = "",
  [switch]$SkipSecondPassRefinement,
  [switch]$SkipGatlingRun
)

$ErrorActionPreference = "Stop"

function Assert-CommandAvailable {
  param([string]$Name)
  if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
    throw "Required command not found in PATH: $Name"
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

  $cmdText = "ssh $($sshArgs -join ' ')"
  $startTs = Get-Date
  Write-Host "[$($startTs.ToString('HH:mm:ss'))] RUN(CAPTURE): $cmdText"

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

  $exitCode = $LASTEXITCODE
  $elapsed = [int]((Get-Date) - $startTs).TotalSeconds
  Write-Host "[$((Get-Date).ToString('HH:mm:ss'))] DONE(CAPTURE) (exit=$exitCode, ${elapsed}s): ssh"

  if ($exitCode -ne 0) {
    throw "Command failed ($exitCode): $cmdText"
  }
  return ($stdout -join "`n")
}

function Invoke-ScpUploadDir {
  param([string]$LocalDir, [string]$RemoteTargetDir)
  $localForScp = $LocalDir -replace "\\", "/"
  $scpArgs = @(
    "-r",
    "-o", "BatchMode=yes",
    "-o", "ConnectTimeout=15",
    "-o", "StrictHostKeyChecking=no",
    "-o", "UserKnownHostsFile=/dev/null",
    "-i", $KeyPath,
    $localForScp,
    "${UserName}@${HostName}:$RemoteTargetDir"
  )
  Invoke-External -Exe "scp" -CmdArgs $scpArgs
}

function Invoke-ScpUploadFile {
  param([string]$LocalFile, [string]$RemoteTargetFile)
  $localForScp = $LocalFile -replace "\\", "/"
  $scpArgs = @(
    "-o", "BatchMode=yes",
    "-o", "ConnectTimeout=15",
    "-o", "StrictHostKeyChecking=no",
    "-o", "UserKnownHostsFile=/dev/null",
    "-i", $KeyPath,
    $localForScp,
    "${UserName}@${HostName}:$RemoteTargetFile"
  )
  Invoke-External -Exe "scp" -CmdArgs $scpArgs
}

function Invoke-ScpDownloadFile {
  param([string]$RemoteFile, [string]$LocalFile)
  $localForScp = $LocalFile -replace "\\", "/"
  $scpArgs = @(
    "-o", "BatchMode=yes",
    "-o", "ConnectTimeout=15",
    "-o", "StrictHostKeyChecking=no",
    "-o", "UserKnownHostsFile=/dev/null",
    "-i", $KeyPath,
    "${UserName}@${HostName}:$RemoteFile",
    $localForScp
  )
  Invoke-External -Exe "scp" -CmdArgs $scpArgs
}

function Invoke-ScpDownloadDir {
  param([string]$RemoteDir, [string]$LocalTargetDir)
  $scpArgs = @(
    "-r",
    "-o", "BatchMode=yes",
    "-o", "ConnectTimeout=15",
    "-o", "StrictHostKeyChecking=no",
    "-o", "UserKnownHostsFile=/dev/null",
    "-i", $KeyPath,
    "${UserName}@${HostName}:$RemoteDir",
    $LocalTargetDir
  )
  Invoke-External -Exe "scp" -CmdArgs $scpArgs
}

function Normalize-ScenarioName {
  param([string]$Value)
  if ([string]::IsNullOrWhiteSpace($Value)) { return "" }
  $normalized = $Value.ToLowerInvariant() -replace '[^a-z0-9]+', ' '
  $normalized = [regex]::Replace($normalized, '\b(script|scripts)\b', ' ')
  $normalized = [regex]::Replace($normalized, '\s+', ' ').Trim()
  return $normalized
}

function Get-NormalizedScenarioId {
  param([string]$Value)
  if ([string]::IsNullOrWhiteSpace($Value)) { return "" }
  $normalized = $Value.ToUpperInvariant() -replace '[^A-Z0-9]+', '_'
  $normalized = [regex]::Replace($normalized, '_+', '_').Trim('_')
  return $normalized
}

function Normalize-ScenarioYaml {
  param(
    [string]$ScenarioYamlPath,
    [string]$NormalizedScenarioId
  )

  if (-not (Test-Path $ScenarioYamlPath)) { return }
  if ([string]::IsNullOrWhiteSpace($NormalizedScenarioId)) { return }

  $lines = Get-Content -Path $ScenarioYamlPath
  $out = New-Object System.Collections.Generic.List[string]
  $topNameUpdated = $false
  $inScenariosBlock = $false

  foreach ($line in $lines) {
    if ($line -match '^scenarios:\s*$') {
      $inScenariosBlock = $true
      $out.Add($line) | Out-Null
      continue
    }

    if ($inScenariosBlock -and $line -match '^[A-Za-z_][A-Za-z0-9_]*:\s*') {
      $inScenariosBlock = $false
    }

    if (-not $topNameUpdated -and $line -match '^name:\s*') {
      $out.Add('name: "' + $NormalizedScenarioId + '"') | Out-Null
      $topNameUpdated = $true
      continue
    }

    if ($inScenariosBlock -and $line -match '^(\s*-\s+name:\s*).*$') {
      $prefix = $matches[1]
      $out.Add($prefix + '"' + $NormalizedScenarioId + '"') | Out-Null
      continue
    }

    if ($inScenariosBlock -and $line -match '^\s+(startUsers|endUsers):\s*') {
      continue
    }

    $out.Add($line) | Out-Null
  }

  Set-Content -Path $ScenarioYamlPath -Value ($out -join "`r`n") -Encoding UTF8
}

function Get-NameSimilarityScore {
  param(
    [string]$RecordingName,
    [string]$CandidateName
  )

  $left = Normalize-ScenarioName -Value $RecordingName
  $right = Normalize-ScenarioName -Value $CandidateName
  if ([string]::IsNullOrWhiteSpace($left) -or [string]::IsNullOrWhiteSpace($right)) { return 0 }
  if ($left -eq $right) { return 1000 }

  $leftTokens = @($left -split ' ' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
  $rightTokens = @($right -split ' ' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
  if ($leftTokens.Count -eq 0 -or $rightTokens.Count -eq 0) { return 0 }

  $common = 0
  foreach ($t in $leftTokens) {
    if ($rightTokens -contains $t) { $common++ }
  }
  if ($common -eq 0) { return 0 }

  $maxCount = [Math]::Max($leftTokens.Count, $rightTokens.Count)
  $score = ($common * 20) + [int](100 * $common / $maxCount)
  if ($right.Contains($left) -or $left.Contains($right)) { $score += 20 }
  return $score
}

function Get-ReferenceScenarioFolder {
  param([string]$RecordingName)
  $candidates = @(
    $RecordingName,
    "$RecordingName-Script",
    ($RecordingName -replace "_Part2$", "_Script_Part2"),
    ($RecordingName -replace "-Regression$", "-Regression-Script")
  ) | Select-Object -Unique
  foreach ($candidate in $candidates) {
    $path = Join-Path $DoneScriptsRoot $candidate
    if (Test-Path $path) {
      return Get-Item $path
    }
  }

  $dirs = @(Get-ChildItem -Path $DoneScriptsRoot -Directory -ErrorAction SilentlyContinue)
  if ($dirs.Count -eq 0) { return $null }

  $best = $null
  $bestScore = -1
  foreach ($dir in $dirs) {
    $score = Get-NameSimilarityScore -RecordingName $RecordingName -CandidateName $dir.Name
    if ($score -gt $bestScore) {
      $bestScore = $score
      $best = $dir
    }
  }

  # Require a meaningful overlap to avoid unrelated matches.
  if ($best -and $bestScore -ge 55) {
    Write-Host "Using fuzzy reference match: '$RecordingName' -> '$($best.Name)' (score=$bestScore)"
    return $best
  }

  return $null
}

function Get-FirstGlobalDataParamsMap {
  param([string]$ScenarioDataPath)
  $map = [ordered]@{}
  if (-not (Test-Path $ScenarioDataPath)) {
    return $map
  }

  $raw = Get-Content -Raw $ScenarioDataPath
  $start = $raw.IndexOf("globalDataSets:")
  if ($start -lt 0) { return $map }
  $tail = $raw.Substring($start)
  $endMarker = $tail.IndexOf("scenarioDataSets:")
  if ($endMarker -gt 0) {
    $tail = $tail.Substring(0, $endMarker)
  }

  $pattern = '(?ms)-\s+name:\s*"?(?<name>[^"\r\n]+)"?\s*\r?\n\s+value:\s*"?(?<value>[^"\r\n]+)"?'
  $matches = [regex]::Matches($tail, $pattern)
  foreach ($m in $matches) {
    $name = $m.Groups["name"].Value.Trim()
    $value = $m.Groups["value"].Value.Trim()
    if (-not $map.Contains($name)) {
      $map[$name] = $value
    }
  }
  return $map
}

function Ensure-ScenarioDataGlobalParams {
  param(
    [string]$ScenarioDataPath,
    [string]$DefaultAuthority = "MillDomain",
    [string]$DefaultPassword = "scale",
    [string]$DefaultUsername = ""
  )
  if (-not (Test-Path $ScenarioDataPath)) { return }

  $raw = Get-Content -Raw $ScenarioDataPath
  if ([string]::IsNullOrWhiteSpace($raw)) { return }

  # Remove invalid top-level scalars if they exist.
  $raw = [regex]::Replace($raw, '(?m)^(authority|username|password)\s*:\s*.*\r?\n', '')

  $globalMap = [ordered]@{}
  $gStart = $raw.IndexOf("globalDataSets:")
  if ($gStart -ge 0) {
    $tail = $raw.Substring($gStart)
    $gEnd = $tail.IndexOf("scenarioDataSets:")
    if ($gEnd -gt 0) { $tail = $tail.Substring(0, $gEnd) }
    $pairPattern = '(?ms)-\s+name:\s*"?(?<name>[^"\r\n]+)"?\s*\r?\n\s+value:\s*"?(?<value>[^"\r\n]+)"?'
    $matches = [regex]::Matches($tail, $pairPattern)
    foreach ($m in $matches) {
      $name = $m.Groups["name"].Value.Trim()
      $value = $m.Groups["value"].Value.Trim()
      if ([string]::IsNullOrWhiteSpace($name)) { continue }
      if (-not $globalMap.Contains($name)) { $globalMap[$name] = $value }
    }
  }

  $usernameIsMissingOrPlaceholder = $true
  if ($globalMap.Contains("username")) {
    $u = [string]$globalMap["username"]
    if (-not [string]::IsNullOrWhiteSpace($u) -and $u -notmatch '^(?i)(username|user_name|null|none|change_me|change-me|changeme|system)$') {
      $usernameIsMissingOrPlaceholder = $false
    }
  }

  if ($usernameIsMissingOrPlaceholder) {
    $preferred = [string]$DefaultUsername
    $derived = ""
    if (-not [string]::IsNullOrWhiteSpace($preferred) -and $preferred -notmatch '^(?i)(username|user_name|null|none|change_me|change-me|changeme|system)$') {
      $derived = $preferred
    }
    foreach ($k in $globalMap.Keys) {
      if ($k -match '^(?i)username(_[a-z0-9]+)?$') {
        $v = [string]$globalMap[$k]
        if (-not [string]::IsNullOrWhiteSpace($v) -and $v -notmatch '^(?i)(username|user_name|null|none|change_me|change-me|changeme)$') {
          $derived = $v
          break
        }
      }
    }
    if ([string]::IsNullOrWhiteSpace($derived)) { $derived = "SYSTEM" }
    $globalMap["username"] = $derived
  }

  # Converter policy: always enforce canonical authority/password values in globalDataSets.
  $globalMap["authority"] = $DefaultAuthority
  $globalMap["password"] = $DefaultPassword

  $paramsBlock = New-Object System.Collections.Generic.List[string]
  foreach ($k in $globalMap.Keys) {
    $v = [string]$globalMap[$k]
    if ([string]::IsNullOrWhiteSpace($v)) { continue }
    $safeK = $k -replace '"', '\"'
    $safeV = $v -replace '"', '\"'
    $paramsBlock.Add('  - name: "' + $safeK + '"')
    $paramsBlock.Add('    value: "' + $safeV + '"')
  }

  $globalBlock = @(
    "globalDataSets:",
    '- queryString: ""',
    "  params:"
  ) + $paramsBlock + @(
    "  headers: null"
  )

  $raw = [regex]::Replace($raw, '(?ms)^globalDataSets:.*?(?=^scenarioDataSets:|\z)', '')
  if ($raw -match '(?m)^scenarioDataSets:') {
    $raw = [regex]::Replace($raw, '(?m)^scenarioDataSets:', ($globalBlock -join "`r`n") + "`r`n" + "scenarioDataSets:")
  } else {
    $raw = $raw.TrimEnd() + "`r`n" + ($globalBlock -join "`r`n") + "`r`n"
  }

  Set-Content -Path $ScenarioDataPath -Value $raw -Encoding utf8
}

function Get-RepliesTransactionJsonMap {
  param([string[]]$RepliesYamlPaths)
  $map = [ordered]@{}
  if (-not $RepliesYamlPaths -or $RepliesYamlPaths.Count -eq 0) { return $map }

  foreach ($path in $RepliesYamlPaths) {
    if ([string]::IsNullOrWhiteSpace($path) -or -not (Test-Path $path)) { continue }

    $lines = Get-Content -Path $path
    for ($i = 0; $i -lt $lines.Count; $i++) {
      $mTx = [regex]::Match($lines[$i], '^\s*-\s*transName:\s*"?(?<tx>[^"\r\n]+)"?\s*$')
      if (-not $mTx.Success) { continue }

      $tx = $mTx.Groups['tx'].Value.Trim()
      if ([string]::IsNullOrWhiteSpace($tx)) { continue }

      $nextTx = $lines.Count
      for ($j = $i + 1; $j -lt $lines.Count; $j++) {
        if ($lines[$j] -match '^\s*-\s*transName:\s*') {
          $nextTx = $j
          break
        }
      }

      $replyIdx = -1
      for ($j = $i + 1; $j -lt $nextTx; $j++) {
        if ($lines[$j] -match '^\s*replyBody:\s*\|-\s*$') {
          $replyIdx = $j
          break
        }
      }
      if ($replyIdx -lt 0) { continue }

      $bodyLines = New-Object System.Collections.Generic.List[string]
      for ($j = $replyIdx + 1; $j -lt $nextTx; $j++) {
        $line = $lines[$j]
        if ($line -match '^\s{6}(.*)$') {
          $bodyLines.Add($Matches[1]) | Out-Null
        } elseif ([string]::IsNullOrWhiteSpace($line)) {
          $bodyLines.Add('') | Out-Null
        }
      }

      if ($bodyLines.Count -eq 0) { continue }
      $normalized = ($bodyLines -join "`n").Trim()
      if ([string]::IsNullOrWhiteSpace($normalized)) { continue }

      try {
        $parsed = $normalized | ConvertFrom-Json -Depth 100
        if (-not $map.Contains($tx)) {
          $map[$tx] = New-Object System.Collections.Generic.List[object]
        }
        $map[$tx].Add($parsed) | Out-Null
      } catch {
        continue
      }
    }
  }

  return $map
}

function Get-ObjectPropertyValue {
  param(
    [object]$InputObject,
    [string]$Name
  )
  if ($null -eq $InputObject -or [string]::IsNullOrWhiteSpace($Name)) { return $null }
  if ($InputObject -is [System.Collections.IDictionary]) {
    if ($InputObject.Contains($Name)) { return $InputObject[$Name] }
  }
  $prop = $InputObject.PSObject.Properties[$Name]
  if ($null -ne $prop) { return $prop.Value }
  return $null
}

function Resolve-ExpressionValueFromReplies {
  param(
    [string]$Expression,
    [System.Collections.IDictionary]$RepliesJsonMap
  )
  if ([string]::IsNullOrWhiteSpace($Expression)) { return "" }
  if (-not ($Expression -match '^\$\{[^}]+\}$')) { return "" }
  if (-not $RepliesJsonMap) { return "" }

  $inner = $Expression.Substring(2, $Expression.Length - 3)
  $dotIndex = $inner.IndexOf('.')
  if ($dotIndex -lt 1) { return "" }

  $transName = $inner.Substring(0, $dotIndex)
  $pathExpr = $inner.Substring($dotIndex + 1)
  if ([string]::IsNullOrWhiteSpace($transName) -or [string]::IsNullOrWhiteSpace($pathExpr)) { return "" }
  if (-not $RepliesJsonMap.Contains($transName)) { return "" }

  $segments = $pathExpr -split '\.'
  $candidates = @()
  $candidateRoot = $RepliesJsonMap[$transName]
  if ($candidateRoot -is [System.Collections.IList]) {
    foreach ($item in $candidateRoot) {
      $candidates += ,$item
    }
  } else {
    $candidates = @($candidateRoot)
  }

  foreach ($candidate in $candidates) {
    $current = $candidate
    $resolved = $true
    foreach ($segmentRaw in $segments) {
      $segment = $segmentRaw.Trim()
      if ([string]::IsNullOrWhiteSpace($segment)) { $resolved = $false; break }

      $m = [regex]::Match($segment, '^(?<name>[A-Za-z_][A-Za-z0-9_]*)(?<idx>(?:\[\d+\])*)$')
      if (-not $m.Success) { $resolved = $false; break }

      $current = Get-ObjectPropertyValue -InputObject $current -Name $m.Groups['name'].Value
      if ($null -eq $current) { $resolved = $false; break }

      $idxMatches = [regex]::Matches($m.Groups['idx'].Value, '\[(?<i>\d+)\]')
      foreach ($idxMatch in $idxMatches) {
        $idx = [int]$idxMatch.Groups['i'].Value
        if ($current -is [System.Collections.IList]) {
          if ($idx -lt 0 -or $idx -ge $current.Count) { $resolved = $false; break }
          $current = $current[$idx]
        } else {
          $resolved = $false
          break
        }
        if ($null -eq $current) { $resolved = $false; break }
      }
      if (-not $resolved) { break }
    }

    if ($resolved -and ($current -is [string] -or $current -is [ValueType])) {
      return [string]$current
    }
  }
  return ""
}

function Resolve-ParamMapDynamicValuesFromReplies {
  param(
    [System.Collections.IDictionary]$ParamMap,
    [string[]]$RepliesYamlPaths
  )
  $resolved = [ordered]@{}
  if ($ParamMap) {
    foreach ($k in $ParamMap.Keys) {
      $resolved[$k] = [string]$ParamMap[$k]
    }
  }
  if (-not $ParamMap -or $ParamMap.Count -eq 0) { return $resolved }

  $repliesMap = Get-RepliesTransactionJsonMap -RepliesYamlPaths $RepliesYamlPaths
  if (-not $repliesMap -or $repliesMap.Count -eq 0) { return $resolved }

  foreach ($k in $resolved.Keys) {
    $v = [string]$resolved[$k]
    if ([string]::IsNullOrWhiteSpace($v)) { continue }
    if ($v.StartsWith('${')) {
      $actual = Resolve-ExpressionValueFromReplies -Expression $v -RepliesJsonMap $repliesMap
      if (-not [string]::IsNullOrWhiteSpace($actual)) {
        $resolved[$k] = $actual
      }
    }
  }
  return $resolved
}

function Get-CanonicalIdentityKeyFromParamName {
  param([string]$Name)
  if ([string]::IsNullOrWhiteSpace($Name)) { return "" }
  $n = $Name.ToLowerInvariant()
  if ($n -match '(^|_)prsnl_id($|_)') { return "prsnl_id" }
  if ($n -match '(^|_)(user_id|userid)($|_)') { return "user_id" }
  if ($n -match '(^|_)person_id($|_)') { return "person_id" }
  if ($n -match '(^|_)(updt_id|update_id)($|_)') { return "updt_id" }
  if ($n -match '(^|_)(encntr_id|encounter_id)($|_)') { return "encntr_id" }
  if ($n -match '(^|_)order_id($|_)') { return "order_id" }
  if ($n -match '(^|_)(referral_id)($|_)') { return "referral_id" }
  if ($n -match '(^|_)(refer_from_provider_id)($|_)') { return "refer_from_provider_id" }
  if ($n -match '(^|_)(fin_num|fin)($|_)') { return "fin_num" }
  if ($n -match '(^|_)(accession_nbr|accession)($|_)') { return "accession_nbr" }
  if ($n -match '(^|_)(authority)($|_)') { return "authority" }
  if ($n -match '(^|_)(password)($|_)') { return "password" }
  if ($n -match '(^|_)(username|user_name)($|_)') { return "username" }
  return ""
}

function Get-IdentityValueFromParamName {
  param([string]$Name)
  if ([string]::IsNullOrWhiteSpace($Name)) { return "" }
  $n = $Name.ToLowerInvariant()

  $patterns = @(
    '^(?:.*_)?person_id_(?<v>\d+)$',
    '^(?:.*_)?accession_(?<v>\d+)$',
    '^(?:.*_)?accession_nbr_(?<v>\d+)$',
    '^(?:.*_)?encntr_id_(?<v>\d+)$',
    '^(?:.*_)?order_id_(?<v>\d+)$',
    '^(?:.*_)?updt_id_(?<v>\d+)$',
    '^(?:.*_)?prsnl_id_(?<v>\d+)$',
    '^(?:.*_)?user_id_(?<v>\d+)$',
    '^(?:.*_)?fin_num_(?<v>\d+)$'
  )
  foreach ($pat in $patterns) {
    $m = [regex]::Match($n, $pat)
    if ($m.Success) {
      return $m.Groups['v'].Value
    }
  }
  return ""
}

function Get-MoveToGlobalStringFromMap {
  param([System.Collections.IDictionary]$MoveMap)
  $pairs = New-Object System.Collections.Generic.List[string]
  $seenValues = @{}
  $keyPriority = @{
    "username" = 10
    "user_id" = 20
    "prsnl_id" = 30
    "person_id" = 40
    "encntr_id" = 50
    "order_id" = 60
    "accession_nbr" = 70
    "updt_id" = 80
    "fin_num" = 90
    "referral_id" = 100
    "refer_from_provider_id" = 110
  }
  if (-not $MoveMap) { return "" }
  $candidates = New-Object System.Collections.Generic.List[object]
  foreach ($k in $MoveMap.Keys) {
    $v = [string]$MoveMap[$k]
    if ([string]::IsNullOrWhiteSpace($v)) { continue }
    if ($k -in @("authority","password","current_dt_tm","current_dt_tm_PastNineYears")) { continue }
    if ($v.StartsWith('${')) { continue }
    $priority = if ($keyPriority.ContainsKey($k)) { [int]$keyPriority[$k] } else { 999 }
    $candidates.Add([pscustomobject]@{ Key = $k; Value = $v; Priority = $priority }) | Out-Null
  }

  foreach ($item in $candidates | Sort-Object Priority, Key) {
    if ($seenValues.ContainsKey($item.Value)) { continue }
    $seenValues[$item.Value] = $true
    [void]$pairs.Add("$($item.Value)`:$($item.Key)")
  }
  if ($pairs.Count -eq 0) { return "" }
  return ($pairs -join ",")
}

function Convert-MoveToGlobalStringToMap {
  param([string]$MoveToGlobal)
  $map = [ordered]@{}
  if ([string]::IsNullOrWhiteSpace($MoveToGlobal)) { return $map }

  $pairs = $MoveToGlobal.Split(',')
  foreach ($rawPair in $pairs) {
    $pair = $rawPair.Trim()
    if ([string]::IsNullOrWhiteSpace($pair)) { continue }

    $idx = $pair.IndexOf(':')
    if ($idx -lt 1 -or $idx -ge ($pair.Length - 1)) { continue }

    $value = $pair.Substring(0, $idx).Trim()
    $key = $pair.Substring($idx + 1).Trim()
    if ([string]::IsNullOrWhiteSpace($value) -or [string]::IsNullOrWhiteSpace($key)) { continue }

    $normalizedKey = $key.Trim().ToLowerInvariant()
    $canonical = ""
    if ($normalizedKey -match '^username_[a-z0-9]+$') {
      $canonical = $normalizedKey
    }
    elseif ($normalizedKey -match '^user_id_[a-z0-9]+$') {
      $canonical = $normalizedKey
    }
    else {
      $canonical = Get-CanonicalIdentityKeyFromParamName -Name $normalizedKey
      if ([string]::IsNullOrWhiteSpace($canonical)) { $canonical = $normalizedKey }
    }
    $map[$canonical] = $value
  }

  return $map
}

function Apply-Pass2PriorityMoveToGlobal {
  param(
    [System.Collections.IDictionary]$MoveMap,
    [string]$PriorityMoveToGlobal
  )

  if (-not $MoveMap) { return }
  if ([string]::IsNullOrWhiteSpace($PriorityMoveToGlobal)) { return }

  $priorityMap = Convert-MoveToGlobalStringToMap -MoveToGlobal $PriorityMoveToGlobal
  if (-not $priorityMap -or $priorityMap.Count -eq 0) {
    Write-Warning "Pass-2 priority override was provided but no valid key:value pairs were parsed: $PriorityMoveToGlobal"
    return
  }

  foreach ($k in $priorityMap.Keys) {
    $v = [string]$priorityMap[$k]
    if ([string]::IsNullOrWhiteSpace($v)) { continue }

    if ($MoveMap.Contains($k) -and ([string]$MoveMap[$k] -ne $v)) {
      Write-Host "Overriding inferred mapping '${k}:$($MoveMap[$k])' with priority mapping '${k}:$v'."
    }
    $MoveMap[$k] = $v

    $duplicateKeys = @()
    foreach ($existingKey in $MoveMap.Keys) {
      if ($existingKey -eq $k) { continue }
      if ([string]$MoveMap[$existingKey] -eq $v) {
        $duplicateKeys += $existingKey
      }
    }

    foreach ($dupKey in $duplicateKeys) {
      [void]$MoveMap.Remove($dupKey)
      Write-Host "Removed duplicate mapping '${dupKey}:$v' to prioritize explicit pass-2 mapping '$k'."
    }
  }

  Write-Host "Applied pass-2 priority move-to-global overrides: $PriorityMoveToGlobal"
}

function Get-MoveToGlobalUsernameMap {
  param([string]$MoveToGlobal)
  $userMap = [ordered]@{}
  if ([string]::IsNullOrWhiteSpace($MoveToGlobal)) { return $userMap }

  $pairs = $MoveToGlobal.Split(',')
  foreach ($rawPair in $pairs) {
    $pair = $rawPair.Trim()
    if ([string]::IsNullOrWhiteSpace($pair)) { continue }

    $idx = $pair.IndexOf(':')
    if ($idx -lt 1 -or $idx -ge ($pair.Length - 1)) { continue }

    $value = $pair.Substring(0, $idx).Trim()
    $key = $pair.Substring($idx + 1).Trim().ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($value) -or [string]::IsNullOrWhiteSpace($key)) { continue }
    if ($key -notmatch '^username(_[a-z0-9]+)?$') { continue }
    if (Is-PlaceholderUsername -Value $value) { continue }
    $userMap[$key] = $value
  }
  return $userMap
}

function Get-UserIdKeyFromUsernameKey {
  param([string]$UsernameKey)
  if ([string]::IsNullOrWhiteSpace($UsernameKey)) { return "user_id" }
  $k = $UsernameKey.Trim().ToLowerInvariant()
  if ($k -match '^username_(?<suffix>[a-z0-9]+)$') {
    return "user_id_$($Matches['suffix'])"
  }
  return "user_id"
}

function Has-MultipleExplicitUsernames {
  param([string]$PriorityMoveToGlobal)
  $userMap = Get-MoveToGlobalUsernameMap -MoveToGlobal $PriorityMoveToGlobal
  if (-not $userMap) { return $false }
  return ($userMap.Count -gt 1)
}

function Add-SqlUserIdsForAllUsernames {
  param(
    [System.Collections.IDictionary]$MoveMap,
    [string]$PriorityMoveToGlobal,
    [string]$DbEnvironment,
    [string]$SqlplusScript
  )
  if (-not $MoveMap) { return }

  $usernameMap = [ordered]@{}

  # Highest priority: explicit prompt-provided username_* overrides.
  $priorityUsers = Get-MoveToGlobalUsernameMap -MoveToGlobal $PriorityMoveToGlobal
  foreach ($k in $priorityUsers.Keys) {
    $usernameMap[$k] = [string]$priorityUsers[$k]
  }

  # Then fill any additional username keys inferred by pass-1.
  foreach ($k in $MoveMap.Keys) {
    if ($k -notmatch '^(?i)username(_[a-z0-9]+)?$') { continue }
    $normKey = $k.ToLowerInvariant()
    $u = [string]$MoveMap[$k]
    if (Is-PlaceholderUsername -Value $u) { continue }
    if (-not $usernameMap.Contains($normKey)) {
      $usernameMap[$normKey] = $u
    }
  }

  if ($usernameMap.Count -eq 0) { return }

  foreach ($usernameKey in $usernameMap.Keys) {
    $username = [string]$usernameMap[$usernameKey]
    if ([string]::IsNullOrWhiteSpace($username)) { continue }
    Write-Host "Attempting SQL user_id lookup for $usernameKey '$username' using DbEnv '$DbEnvironment'..."
    $sqlUserId = Get-UserIdFromSqlplusByUsername -Username $username -DbEnvironment $DbEnvironment -SqlplusScript $SqlplusScript
    if ([string]::IsNullOrWhiteSpace($sqlUserId)) { continue }

    $targetUserIdKey = Get-UserIdKeyFromUsernameKey -UsernameKey $usernameKey
    if ($MoveMap.Contains($targetUserIdKey) -and ([string]$MoveMap[$targetUserIdKey] -ne $sqlUserId)) {
      Write-Host "Overriding inferred mapping '${targetUserIdKey}:$($MoveMap[$targetUserIdKey])' with SQL-derived value '$sqlUserId'."
    }
    $MoveMap[$targetUserIdKey] = $sqlUserId
    Write-Host "SQL-derived mapping applied: ${sqlUserId}:$targetUserIdKey (from $usernameKey)."
  }
}

function Apply-UsernameAnnotationReplacements {
  param(
    [string]$ConvertedDir,
    [System.Collections.IDictionary]$MoveMap
  )
  if ([string]::IsNullOrWhiteSpace($ConvertedDir) -or -not (Test-Path $ConvertedDir)) { return }
  if (-not $MoveMap -or $MoveMap.Count -eq 0) { return }

  $replacementRows = New-Object System.Collections.Generic.List[object]
  foreach ($k in $MoveMap.Keys) {
    if ($k -notmatch '^(?i)username(_[a-z0-9]+)?$') { continue }
    $v = [string]$MoveMap[$k]
    if ([string]::IsNullOrWhiteSpace($v)) { continue }
    if (Is-PlaceholderUsername -Value $v) { continue }
    $replacementRows.Add([pscustomobject]@{ Value = $v; Key = $k.ToLowerInvariant() }) | Out-Null
  }
  if ($replacementRows.Count -eq 0) { return }

  $valueToKey = @{}
  function Get-UsernameKeyPriority {
    param([string]$Key)
    if ([string]::IsNullOrWhiteSpace($Key)) { return 999 }
    if ($Key.ToLowerInvariant() -eq "username") { return 200 }
    return 100
  }
  foreach ($row in $replacementRows) {
    $val = [string]$row.Value
    $key = [string]$row.Key
    if ([string]::IsNullOrWhiteSpace($val) -or [string]::IsNullOrWhiteSpace($key)) { continue }
    $lk = $val.ToLowerInvariant()
    if (-not $valueToKey.ContainsKey($lk)) {
      $valueToKey[$lk] = $key
      continue
    }
    $existing = [string]$valueToKey[$lk]
    if ((Get-UsernameKeyPriority -Key $key) -lt (Get-UsernameKeyPriority -Key $existing)) {
      $valueToKey[$lk] = $key
    }
  }

  function Get-UsernameAnnotationForValue {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return "" }
    $lookup = $Value.Trim().ToLowerInvariant()
    if ($valueToKey.ContainsKey($lookup)) {
      return '$' + '{' + [string]$valueToKey[$lookup] + '}'
    }
    return ""
  }

  $scenarioPath = Join-Path $ConvertedDir "scenario.yaml"
  $scenarioDataPath = Join-Path $ConvertedDir "scenario-data.yaml"
  if (-not (Test-Path $scenarioPath) -and -not (Test-Path $scenarioDataPath)) { return }

  if (Test-Path $scenarioPath) {
    $raw = Get-Content -Raw $scenarioPath
    $updated = $raw

    # Replace JSON user/username fields, including request bodies outside instanceJson.
    $updated = [regex]::Replace(
      $updated,
      '(?<prefix>"(?:username|user)(?:_[a-z0-9]+)?"\s*:\s*")(?<val>[^"\r\n]+)(?<suffix>")',
      {
        param($m)
        $annotation = Get-UsernameAnnotationForValue -Value $m.Groups["val"].Value
        if ([string]::IsNullOrWhiteSpace($annotation)) { return $m.Value }
        return $m.Groups["prefix"].Value + $annotation + $m.Groups["suffix"].Value
      },
      [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    )

    # Replace YAML user/username fields (quoted or unquoted).
    $updated = [regex]::Replace(
      $updated,
      '(?im)^(?<prefix>\s*(?:username|user)(?:_[a-z0-9]+)?\s*:\s*)(?<q>["'']?)(?<val>[^"''\r\n#]+)(?<q2>["'']?)',
      {
        param($m)
        $annotation = Get-UsernameAnnotationForValue -Value $m.Groups["val"].Value
        if ([string]::IsNullOrWhiteSpace($annotation)) { return $m.Value }
        $q = $m.Groups["q"].Value
        $q2 = $m.Groups["q2"].Value
        if ([string]::IsNullOrWhiteSpace($q) -or [string]::IsNullOrWhiteSpace($q2)) {
          return $m.Groups["prefix"].Value + $annotation
        }
        return $m.Groups["prefix"].Value + $q + $annotation + $q2
      }
    )

    if ($updated -ne $raw) {
      Set-Content -Path $scenarioPath -Value $updated
      Write-Host "Applied username annotation replacement pass: $scenarioPath"
    }
  }

  if (Test-Path $scenarioDataPath) {
    $lines = Get-Content -Path $scenarioDataPath
    $out = New-Object System.Collections.Generic.List[string]
    $pendingParamName = ""
    $changed = $false

    function Get-UsernameLiteralForParam {
      param(
        [string]$ParamName,
        [string]$CurrentValue
      )

      if ([string]::IsNullOrWhiteSpace($ParamName)) { return "" }
      $normalizedParam = $ParamName.Trim().ToLowerInvariant()
      if ($normalizedParam -notmatch '^(username|user)(_[a-z0-9]+)?$') { return "" }

      # Prefer explicit keyed mapping (username_a, username_b, ...).
      if ($MoveMap.Contains($normalizedParam)) {
        $mapped = [string]$MoveMap[$normalizedParam]
        if (-not [string]::IsNullOrWhiteSpace($mapped) -and -not (Is-PlaceholderUsername -Value $mapped)) {
          return $mapped
        }
      }

      # If current value is annotation, resolve through MoveMap.
      if (-not [string]::IsNullOrWhiteSpace($CurrentValue)) {
        $mAnno = [regex]::Match($CurrentValue.Trim(), '^\$\{(?<key>username(?:_[a-z0-9]+)?)\}$', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if ($mAnno.Success) {
          $annoKey = $mAnno.Groups['key'].Value.ToLowerInvariant()
          if ($MoveMap.Contains($annoKey)) {
            $mappedAnno = [string]$MoveMap[$annoKey]
            if (-not [string]::IsNullOrWhiteSpace($mappedAnno) -and -not (Is-PlaceholderUsername -Value $mappedAnno)) {
              return $mappedAnno
            }
          }
        }
      }

      # Fallback to generic username mapping if available.
      if ($MoveMap.Contains("username")) {
        $generic = [string]$MoveMap["username"]
        if (-not [string]::IsNullOrWhiteSpace($generic) -and -not (Is-PlaceholderUsername -Value $generic)) {
          return $generic
        }
      }
      return ""
    }

    foreach ($line in $lines) {
      $nameMatch = [regex]::Match($line, '^\s*-\s+name:\s*"?(?<name>[^"\r\n]+)"?')
      if ($nameMatch.Success) {
        $pendingParamName = $nameMatch.Groups["name"].Value.Trim()
        $out.Add($line) | Out-Null
        continue
      }

      $valueMatch = [regex]::Match($line, '^(?<prefix>\s*value:\s*")(?<val>[^"\r\n]+)(?<suffix>")\s*$')
      if ($valueMatch.Success -and -not [string]::IsNullOrWhiteSpace($pendingParamName)) {
        if ($pendingParamName -match '^(?i)(username|user)(_[a-z0-9]+)?$') {
          $literal = Get-UsernameLiteralForParam -ParamName $pendingParamName -CurrentValue $valueMatch.Groups["val"].Value
          if (-not [string]::IsNullOrWhiteSpace($literal)) {
            $out.Add($valueMatch.Groups["prefix"].Value + $literal + $valueMatch.Groups["suffix"].Value) | Out-Null
            $changed = $true
            $pendingParamName = ""
            continue
          }
        }
      }

      $out.Add($line) | Out-Null
      if ($line -notmatch '^\s*$') {
        $pendingParamName = ""
      }
    }

    if ($changed) {
      Set-Content -Path $scenarioDataPath -Value ($out -join "`r`n")
      Write-Host "Applied username annotation replacement pass: $scenarioDataPath"
    }
  }
}

function Get-IdentityMoveMapFromScenarioAndReplies {
  param(
    [string]$ScenarioDataPath,
    [string[]]$RepliesYamlPaths
  )
  $map = [ordered]@{}
  if (-not (Test-Path $ScenarioDataPath)) { return $map }

  $repliesMap = Get-RepliesTransactionJsonMap -RepliesYamlPaths $RepliesYamlPaths
  $canonicalOrder = New-Object System.Collections.Generic.List[string]
  $valueCountsByCanonical = @{}
  $valueOrderByCanonical = @{}
  $raw = Get-Content -Raw $ScenarioDataPath
  $pattern = '(?ms)-\s+name:\s*"?(?<name>[^"\r\n]+)"?\s*\r?\n\s+value:\s*"?(?<value>[^"\r\n]+)"?'
  $matches = [regex]::Matches($raw, $pattern)
  function Add-CanonicalValueCount {
    param(
      [string]$CanonicalKey,
      [string]$ResolvedValue
    )
    if ([string]::IsNullOrWhiteSpace($CanonicalKey) -or [string]::IsNullOrWhiteSpace($ResolvedValue)) { return }
    if (-not $valueCountsByCanonical.ContainsKey($CanonicalKey)) {
      $valueCountsByCanonical[$CanonicalKey] = @{}
      $valueOrderByCanonical[$CanonicalKey] = New-Object System.Collections.Generic.List[string]
      [void]$canonicalOrder.Add($CanonicalKey)
    }
    if (-not $valueCountsByCanonical[$CanonicalKey].ContainsKey($ResolvedValue)) {
      $valueCountsByCanonical[$CanonicalKey][$ResolvedValue] = 0
      [void]$valueOrderByCanonical[$CanonicalKey].Add($ResolvedValue)
    }
    $valueCountsByCanonical[$CanonicalKey][$ResolvedValue] = [int]$valueCountsByCanonical[$CanonicalKey][$ResolvedValue] + 1
  }

  foreach ($m in $matches) {
    $name = $m.Groups["name"].Value.Trim()
    $value = $m.Groups["value"].Value.Trim()
    if ([string]::IsNullOrWhiteSpace($name) -or [string]::IsNullOrWhiteSpace($value)) { continue }

    $canonical = Get-CanonicalIdentityKeyFromParamName -Name $name
    if ([string]::IsNullOrWhiteSpace($canonical)) { continue }
    if ($canonical -in @("authority","password")) { continue }

    $resolved = $value
    if ($value.StartsWith('${')) {
      $resolved = Resolve-ExpressionValueFromReplies -Expression $value -RepliesJsonMap $repliesMap
    }
    if ([string]::IsNullOrWhiteSpace($resolved) -or $resolved.StartsWith('${')) {
      # Fallback for identity params where value is encoded in the param name
      # (for example person_id_<id>, accession_<id>).
      $resolved = Get-IdentityValueFromParamName -Name $name
    }
    if ([string]::IsNullOrWhiteSpace($resolved) -or $resolved.StartsWith('${')) { continue }

    Add-CanonicalValueCount -CanonicalKey $canonical -ResolvedValue $resolved

    # User identity aliasing: prsnl_id is commonly the source for user_id.
    if ($canonical -eq "prsnl_id") {
      Add-CanonicalValueCount -CanonicalKey "user_id" -ResolvedValue $resolved
    }
  }

  function Get-IdentityValueQualityScore {
    param(
      [string]$CanonicalKey,
      [string]$Value
    )
    if ([string]::IsNullOrWhiteSpace($Value)) { return -1 }
    $v = $Value.Trim()

    if ($CanonicalKey -eq "accession_nbr") {
      if ($v -match '^\d{15,}$') { return 400 + [Math]::Min($v.Length, 99) }
      if ($v -match '^\d{10,14}$') { return 300 + $v.Length }
      if ($v -match '^\d+$') { return 200 + $v.Length }
      if ($v -match '^[A-Za-z0-9\-]+$') { return 100 + [Math]::Min($v.Length, 50) }
      return 0
    }

    return 0
  }

  foreach ($canonical in $canonicalOrder) {
    $bestValue = ""
    $bestCount = -1
    $bestScore = -1
    foreach ($candidateValue in $valueOrderByCanonical[$canonical]) {
      $count = [int]$valueCountsByCanonical[$canonical][$candidateValue]
      $score = Get-IdentityValueQualityScore -CanonicalKey $canonical -Value $candidateValue
      $shouldReplace = $false
      if ($canonical -eq 'accession_nbr') {
        # For accession values, prefer strong numeric identifiers over short alpha tokens.
        if ($score -gt $bestScore -or ($score -eq $bestScore -and $count -gt $bestCount)) {
          $shouldReplace = $true
        }
      }
      else {
        if ($count -gt $bestCount -or ($count -eq $bestCount -and $score -gt $bestScore)) {
          $shouldReplace = $true
        }
      }
      if ($shouldReplace) {
        $bestCount = $count
        $bestScore = $score
        $bestValue = $candidateValue
      }
    }
    if (-not [string]::IsNullOrWhiteSpace($bestValue) -and -not $map.Contains($canonical)) {
      $map[$canonical] = $bestValue
    }
  }
  return $map
}

function Get-SqlSectionKeys {
  param(
    [string]$SqlText,
    [string]$ScenarioName
  )
  $keys = New-Object System.Collections.Generic.List[string]
  if ([string]::IsNullOrWhiteSpace($SqlText)) { return $keys }

  $escapedName = [regex]::Escape($ScenarioName)
  $sectionPattern = "(?ms)^\s*$escapedName\s*:\s*\r?\n-+\s*\r?\n(?<body>.*?)(?:^\s*[A-Za-z0-9_\-]+\s*:\s*\r?\n-+|^\s*=+|\z)"
  $m = [regex]::Match($SqlText, $sectionPattern)
  if (-not $m.Success) {
    return $keys
  }
  $body = $m.Groups["body"].Value

  $aliasMatches = [regex]::Matches($body, '(?i)\bAS\s+([A-Za-z_][A-Za-z0-9_]*)')
  foreach ($am in $aliasMatches) {
    $k = $am.Groups[1].Value
    if (-not $keys.Contains($k)) { [void]$keys.Add($k) }
  }

  $important = @(
    "person_id","updt_id","encntr_id","order_id","referral_id","refer_from_provider_id",
    "fin_num","prsnl_id","username","username_a","username_b","username_c",
    "user_id_a","user_id_b","user_id_c","accession_nbr","authority","password",
    "current_dt_tm","current_dt_tm_PastNineYears"
  )
  foreach ($k in $important) {
    if ($body -match ("(?i)\b" + [regex]::Escape($k) + "\b")) {
      if (-not $keys.Contains($k)) { [void]$keys.Add($k) }
    }
  }
  return $keys
}

function Is-PlaceholderUsername {
  param([string]$Value)
  if ([string]::IsNullOrWhiteSpace($Value)) { return $true }
  return ($Value -match '^(?i)(username|user_name|null|none|change_me|change-me|changeme|system)$')
}

function Get-PreferredUsernameForLookup {
  param(
    [System.Collections.IDictionary]$DerivedIdentityMap,
    [System.Collections.IDictionary]$ParamMap
  )
  if ($DerivedIdentityMap -and $DerivedIdentityMap.Contains("username")) {
    $u = [string]$DerivedIdentityMap["username"]
    if (-not (Is-PlaceholderUsername -Value $u)) { return $u }
  }
  if ($ParamMap) {
    foreach ($k in $ParamMap.Keys) {
      if ($k -match '^(?i)username(_[a-z0-9]+)?$') {
        $u = [string]$ParamMap[$k]
        if (-not (Is-PlaceholderUsername -Value $u)) { return $u }
      }
    }
  }
  return ""
}

function Get-UserIdFromSqlplusByUsername {
  param(
    [string]$Username,
    [string]$DbEnvironment,
    [string]$SqlplusScript
  )
  if ([string]::IsNullOrWhiteSpace($Username)) { return "" }
  if (-not (Test-Path $SqlplusScript)) {
    Write-Warning "sqlplus runner script not found: $SqlplusScript"
    return ""
  }

  $safeUsername = $Username.Replace("'", "''")
  $query = "SELECT person_id AS user_id FROM PRSNL p WHERE UPPER(username) = UPPER('$safeUsername');"
  $cmdArgs = @(
    "-NoProfile",
    "-File", $SqlplusScript,
    "-DbEnv", $DbEnvironment,
    "-Query", $query,
    "-OutputFormat", "csv"
  )

  $cmdText = "pwsh $($cmdArgs -join ' ')"
  $startTs = Get-Date
  Write-Host "[$($startTs.ToString('HH:mm:ss'))] RUN(CAPTURE): $cmdText"

  $output = & pwsh @cmdArgs 2>&1
  $stdout = New-Object System.Collections.Generic.List[string]
  foreach ($line in $output) {
    if ($null -eq $line) { continue }
    $text = [string]$line
    if ([string]::IsNullOrWhiteSpace($text)) { continue }
    Write-Host "[$((Get-Date).ToString('HH:mm:ss'))] $text"
    if ($line -is [System.Management.Automation.ErrorRecord]) { continue }
    $stdout.Add($text) | Out-Null
  }

  $exitCode = $LASTEXITCODE
  $elapsed = [int]((Get-Date) - $startTs).TotalSeconds
  Write-Host "[$((Get-Date).ToString('HH:mm:ss'))] DONE(CAPTURE) (exit=$exitCode, ${elapsed}s): pwsh"
  if ($exitCode -ne 0) {
    Write-Warning "sqlplus lookup failed for username '$Username' on '$DbEnvironment' (exit=$exitCode)."
    return ""
  }

  foreach ($raw in $stdout) {
    $line = ($raw -replace "`e\[[\d;]*[A-Za-z]", "").Trim()
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    if ($line -match '^(?i)user_id$') { continue }
    if ($line -match '^(?i)\d+\s+rows?\s+selected\.?$') { continue }
    if ($line -match '^-+$') { continue }
    $first = $line.Split(',')[0].Trim().Trim('"')
    if ($first -match '^\d+$') {
      return $first
    }
  }

  Write-Warning "sqlplus lookup returned no numeric user_id for username '$Username' on '$DbEnvironment'."
  return ""
}

function Get-MoveToGlobalString {
  param(
    [System.Collections.Generic.List[string]]$OrderedKeys,
    [System.Collections.IDictionary]$ParamMap
  )
  $pairs = New-Object System.Collections.Generic.List[string]
  $seenValues = @{}
  $keyPriority = @{
    "username" = 10
    "user_id" = 20
    "prsnl_id" = 30
    "person_id" = 40
    "encntr_id" = 50
    "order_id" = 60
    "accession_nbr" = 70
    "updt_id" = 80
    "fin_num" = 90
    "referral_id" = 100
    "refer_from_provider_id" = 110
  }
  $candidates = New-Object System.Collections.Generic.List[object]
  foreach ($k in $OrderedKeys) {
    if (-not $ParamMap.Contains($k)) { continue }
    $v = [string]$ParamMap[$k]
    if ([string]::IsNullOrWhiteSpace($v)) { continue }
    if ($k -in @("authority","password","current_dt_tm","current_dt_tm_PastNineYears")) { continue }
    if ($v.StartsWith('${')) { continue }
    $priority = if ($keyPriority.ContainsKey($k)) { [int]$keyPriority[$k] } else { 999 }
    $candidates.Add([pscustomobject]@{ Key = $k; Value = $v; Priority = $priority }) | Out-Null
  }
  foreach ($item in $candidates | Sort-Object Priority, Key) {
    if ($seenValues.ContainsKey($item.Value)) { continue }
    $seenValues[$item.Value] = $true
    [void]$pairs.Add("$($item.Value)`:$($item.Key)")
  }
  if ($pairs.Count -eq 0) { return "" }
  return ($pairs -join ",")
}

function Convert-RecordingRemote {
  param(
    [string]$RecordingDir,
    [string]$MoveToGlobal,
    [bool]$SkipConverterUsernameArg = $false
  )

  $recordingName = Split-Path $RecordingDir -Leaf
  $timestamp = Get-Date -Format "yyyyMMddHHmmss"
  $rand = [System.Guid]::NewGuid().ToString("N").Substring(0, 8)
  $remoteBase = "/root/gatling/gatling-converter-$timestamp-$rand"
  $remoteInputRoot = "$remoteBase/input"
  $remoteOutputRoot = "$remoteBase/output"
  $remoteRecordingPath = "$remoteInputRoot/$recordingName"

  Write-Host "Creating remote working directory: $remoteBase"
  Invoke-Ssh "mkdir -p '$remoteInputRoot' '$remoteOutputRoot'"

  $uploadTempRoot = Join-Path $env:TEMP "gatling_converter_uploads"
  New-Item -ItemType Directory -Force -Path $uploadTempRoot | Out-Null
  $localArchive = Join-Path $uploadTempRoot "$recordingName-$timestamp.tar.gz"
  $recordingParent = Split-Path $RecordingDir -Parent
  $recordingLeaf = Split-Path $RecordingDir -Leaf
  $remoteArchive = "$remoteBase/$recordingName-$timestamp.tar.gz"

  try {
    Write-Host "Compressing recording for upload: $recordingName"
    $tarArgs = @(
      "-czf", $localArchive,
      "-C", $recordingParent,
      $recordingLeaf
    )
    Invoke-External -Exe "tar" -CmdArgs $tarArgs

    Write-Host "Uploading compressed recording archive: $([IO.Path]::GetFileName($localArchive))"
    Invoke-ScpUploadFile -LocalFile $localArchive -RemoteTargetFile $remoteArchive

    Write-Host "Extracting archive on remote host..."
    Invoke-Ssh "tar -xzf '$remoteArchive' -C '$remoteInputRoot'"
    Invoke-Ssh "rm -f '$remoteArchive'"
  }
  finally {
    if (Test-Path $localArchive) {
      Remove-Item -Force -Path $localArchive -ErrorAction SilentlyContinue
    }
  }

  $remoteRecordingPath = (Get-SshOutput "find '$remoteInputRoot' -mindepth 1 -maxdepth 1 -type d | head -n 1").Trim()
  if ([string]::IsNullOrWhiteSpace($remoteRecordingPath)) {
    throw "Upload failed: no recording directory found under remote input root $remoteInputRoot"
  }
  Write-Host "Resolved remote recording path: $remoteRecordingPath"

  Write-Host "Removing noise folders (cernserver*/discernnotify*)"
  Invoke-Ssh "find '$remoteRecordingPath' -maxdepth 1 -type d \( -name 'cernserver*' -o -name 'discernnotify*' \) -exec rm -rf {} + 2>/dev/null || true"

  $combineCountCmd = "find '$remoteRecordingPath' -mindepth 1 -maxdepth 1 -type d | wc -l"
  $combineCount = (Get-SshOutput $combineCountCmd).Trim()
  if (-not $combineCount) { $combineCount = "0" }

  $workflowJarCmd = "ls -1 /root/gatling/*workflow*converter*.jar /root/gatling/workflow-converter*.jar 2>/dev/null | head -n 1"
  $workflowJar = (Get-SshOutput $workflowJarCmd).Trim()
  if ([string]::IsNullOrWhiteSpace($workflowJar)) {
    throw "workflow-converter jar not found in /root/gatling on remote host."
  }

  $remoteInputForConverter = $remoteRecordingPath
  if ([int]$combineCount -le 1) {
    $singleChild = (Get-SshOutput "find '$remoteRecordingPath' -mindepth 1 -maxdepth 1 -type d | head -n 1").Trim()
    if (-not [string]::IsNullOrWhiteSpace($singleChild)) {
      $remoteInputForConverter = $singleChild
    }
  }

  $converterArgs = @(
    "java -jar '$workflowJar'",
    "-input '$remoteInputForConverter'",
    "-output '$remoteOutputRoot'",
    "-password '`${password}'",
    "-authority '`${authority}'",
    "-request-format YAML",
    "-reply-format YAML",
    "-time-zone '$TimeZone'",
    "--acsv",
    "-n_cd",
    "-dh $TargetAlias"
  )
  if (-not $SkipConverterUsernameArg) {
    $converterArgs += "-username '`${username}'"
  } else {
    Write-Host "Skipping workflow-converter username argument because multiple explicit username_* overrides were supplied."
  }
  if ([int]$combineCount -gt 1) {
    $converterArgs += "--combine"
  }
  if (-not [string]::IsNullOrWhiteSpace($MoveToGlobal)) {
    $converterArgs += "--move-to-global '$MoveToGlobal'"
  }
  $remoteConverterCmd = $converterArgs -join " "
  Write-Host "Running remote converter..."
  Invoke-Ssh $remoteConverterCmd

  $localDownloadRoot = Join-Path $env:TEMP "gatling_converter_downloads"
  New-Item -ItemType Directory -Force -Path $localDownloadRoot | Out-Null
  $localTarget = Join-Path $localDownloadRoot "$recordingName-$timestamp"
  New-Item -ItemType Directory -Force -Path $localTarget | Out-Null

  $remoteOutputArchive = "$remoteBase/output-$recordingName-$timestamp.tar.gz"
  $localOutputArchive = Join-Path $localTarget "output-$recordingName-$timestamp.tar.gz"

  Write-Host "Compressing converter output on remote host..."
  Invoke-Ssh "set -e; tar -czf '$remoteOutputArchive' -C '$remoteBase' output"

  Write-Host "Downloading compressed converter output..."
  Invoke-ScpDownloadFile -RemoteFile $remoteOutputArchive -LocalFile $localOutputArchive

  Write-Host "Extracting downloaded converter archive..."
  $tarExtractArgs = @(
    "-xzf", $localOutputArchive,
    "-C", $localTarget
  )
  Invoke-External -Exe "tar" -CmdArgs $tarExtractArgs

  if (Test-Path $localOutputArchive) {
    Remove-Item -Force -Path $localOutputArchive -ErrorAction SilentlyContinue
  }

  Invoke-Ssh "rm -rf '$remoteBase'" 
  return $localTarget
}

function Resolve-ConvertedScenarioDir {
  param([string]$DownloadedRoot)
  $scenarioFiles = Get-ChildItem -Path $DownloadedRoot -Recurse -Filter "scenario.yaml" -ErrorAction SilentlyContinue | Where-Object { -not $_.PSIsContainer }
  if (-not $scenarioFiles -or $scenarioFiles.Count -eq 0) {
    throw "No scenario.yaml found in converter output under $DownloadedRoot"
  }
  $candidate = $scenarioFiles | Sort-Object FullName | Select-Object -First 1
  return Split-Path $candidate.FullName -Parent
}

function Prepare-RunnerScenario {
  param(
    [string]$ScenarioName,
    [string]$ConvertedDir,
    [string]$ReferenceDir,
    [System.Collections.IDictionary]$DerivedIdentityMap
  )
  $generatedDir = Join-Path $GeneratedScriptsRoot $ScenarioName
  $runnerDir = Join-Path "C:/Users/prakash/Desktop/project/NBS/gatling/script" $ScenarioName
  $normalizedScenarioId = Get-NormalizedScenarioId -Value $ScenarioName
  foreach ($dir in @($generatedDir, $runnerDir)) {
    if (Test-Path $dir) { Remove-Item -Recurse -Force $dir }
    New-Item -ItemType Directory -Path $dir | Out-Null

    $targetScenarioYaml = Join-Path $dir "scenario.yaml"
    Copy-Item -Path (Join-Path $ConvertedDir "scenario.yaml") -Destination $targetScenarioYaml -Force
    Normalize-ScenarioYaml -ScenarioYamlPath $targetScenarioYaml -NormalizedScenarioId $normalizedScenarioId
    $targetScenarioData = Join-Path $dir "scenario-data.yaml"
    Copy-Item -Path (Join-Path $ConvertedDir "scenario-data.yaml") -Destination $targetScenarioData -Force

    $replyFiles = Get-ChildItem -Path $ConvertedDir -Filter "replies*.yaml" -ErrorAction SilentlyContinue | Where-Object { -not $_.PSIsContainer }
    foreach ($rf in $replyFiles) {
      Copy-Item -Path $rf.FullName -Destination (Join-Path $dir $rf.Name) -Force
    }

    $refConfig = $null
    if ($ReferenceDir) {
      $cfgPath = Join-Path $ReferenceDir "config.yaml"
      if (Test-Path $cfgPath) { $refConfig = $cfgPath }
    }
    if ($refConfig) {
      Copy-Item -Path $refConfig -Destination (Join-Path $dir "config.yaml") -Force
    } else {
      @"
authority: $TargetAlias
username: SYSTEM
password: system
verboseLogging: true
"@ | Set-Content -Path (Join-Path $dir "config.yaml")
    }

    # Ensure authority/password/username are placed under globalDataSets params (not top-level).
    $preferredUsername = ""
    if ($DerivedIdentityMap -and $DerivedIdentityMap.Contains("username")) {
      $preferredUsername = [string]$DerivedIdentityMap["username"]
    }
    Ensure-ScenarioDataGlobalParams -ScenarioDataPath $targetScenarioData -DefaultAuthority "MillDomain" -DefaultPassword "scale" -DefaultUsername $preferredUsername
  }
  return $runnerDir
}

function ConvertTo-SafeFileSegment {
  param([string]$Value)
  if ([string]::IsNullOrWhiteSpace($Value)) { return "unknown" }
  $safe = $Value -replace '[^A-Za-z0-9_\-]+', '_'
  $safe = [regex]::Replace($safe, '_+', '_').Trim('_')
  if ([string]::IsNullOrWhiteSpace($safe)) { return "unknown" }
  return $safe
}

function Get-ScenarioTransactionAnnotationStats {
  param([string]$ScenarioYamlPath)

  $stats = [ordered]@{
    TotalTransactions = 0
    AnnotatedTransactions = 0
    UnannotatedTransactions = 0
    TotalAnnotationTokens = 0
    Rows = @()
  }
  if (-not (Test-Path $ScenarioYamlPath)) { return $stats }

  $lines = Get-Content -Path $ScenarioYamlPath
  $currentName = ""
  $currentHasAnnotation = $false
  $currentTokenCount = 0
  $rows = New-Object System.Collections.Generic.List[object]

  function Close-TransactionBlock {
    param([string]$Name, [bool]$HasAnnotation, [int]$TokenCount)
    if ([string]::IsNullOrWhiteSpace($Name)) { return }
    $rows.Add([pscustomobject]@{
      transName = $Name
      hasAnnotation = $HasAnnotation
      annotationTokens = $TokenCount
    }) | Out-Null
  }

  foreach ($line in $lines) {
    $transMatch = [regex]::Match($line, '^\s*-\s+transName:\s*"?(?<name>[^"\r\n]+)"?')
    if ($transMatch.Success) {
      Close-TransactionBlock -Name $currentName -HasAnnotation $currentHasAnnotation -TokenCount $currentTokenCount
      $currentName = $transMatch.Groups["name"].Value.Trim()
      $currentHasAnnotation = $false
      $currentTokenCount = 0
      continue
    }

    if ([string]::IsNullOrWhiteSpace($currentName)) { continue }
    $tokenMatches = [regex]::Matches($line, '\$\{[^}]+\}')
    if ($tokenMatches.Count -gt 0) {
      $currentHasAnnotation = $true
      $currentTokenCount += $tokenMatches.Count
    }
  }
  Close-TransactionBlock -Name $currentName -HasAnnotation $currentHasAnnotation -TokenCount $currentTokenCount

  $stats["Rows"] = @($rows.ToArray())
  $stats["TotalTransactions"] = [int]$rows.Count
  $annotated = @($rows | Where-Object { $_.hasAnnotation })
  $stats["AnnotatedTransactions"] = [int]$annotated.Count
  $stats["UnannotatedTransactions"] = [int]($rows.Count - $annotated.Count)
  $sumTokens = ($rows | Measure-Object -Property annotationTokens -Sum).Sum
  if ($null -eq $sumTokens) { $sumTokens = 0 }
  $stats["TotalAnnotationTokens"] = [int]$sumTokens
  return $stats
}

function Get-ScenarioDataAnnotationActualRows {
  param(
    [string]$ScenarioDataPath,
    [string[]]$RepliesYamlPaths
  )
  $rows = New-Object System.Collections.Generic.List[object]
  if (-not (Test-Path $ScenarioDataPath)) { return @($rows.ToArray()) }

  $maxRepliesBytesForResolution = 20000000
  $totalRepliesBytes = 0
  foreach ($rp in $RepliesYamlPaths) {
    if (-not (Test-Path $rp)) { continue }
    $fi = Get-Item $rp -ErrorAction SilentlyContinue
    if ($fi) { $totalRepliesBytes += [int64]$fi.Length }
  }

  $canResolveActualValues = ($totalRepliesBytes -le $maxRepliesBytesForResolution)
  $repliesMap = @{}
  if ($canResolveActualValues) {
    $repliesMap = Get-RepliesTransactionJsonMap -RepliesYamlPaths $RepliesYamlPaths
  }
  $lines = Get-Content -Path $ScenarioDataPath
  $currentTransName = ""
  $pendingParamName = ""

  foreach ($line in $lines) {
    $transMatch = [regex]::Match($line, '^\s*-\s+transName:\s*"?(?<name>[^"\r\n]+)"?')
    if ($transMatch.Success) {
      $currentTransName = $transMatch.Groups["name"].Value.Trim()
      $pendingParamName = ""
      continue
    }

    $nameMatch = [regex]::Match($line, '^\s*-\s+name:\s*"?(?<name>[^"\r\n]+)"?')
    if ($nameMatch.Success) {
      $pendingParamName = $nameMatch.Groups["name"].Value.Trim()
      continue
    }

    if ([string]::IsNullOrWhiteSpace($pendingParamName)) { continue }

    $valueMatch = [regex]::Match($line, '^\s+value:\s*"?(?<value>[^"\r\n]+)"?')
    if (-not $valueMatch.Success) { continue }

    $annotationValue = $valueMatch.Groups["value"].Value.Trim()
    if ($annotationValue.StartsWith('${')) {
      $actualValue = ""
      if ($canResolveActualValues) {
        $actualValue = Resolve-ExpressionValueFromReplies -Expression $annotationValue -RepliesJsonMap $repliesMap
        if ([string]::IsNullOrWhiteSpace($actualValue)) { $actualValue = "<unresolved>" }
      } else {
        $actualValue = "<skipped_large_replies_payload>"
      }
      $rows.Add([pscustomobject]@{
        transName = $currentTransName
        paramName = $pendingParamName
        annotation = $annotationValue
        actualValue = $actualValue
      }) | Out-Null
    }
    $pendingParamName = ""
  }

  return @($rows.ToArray())
}

function Write-ConversionYamlReport {
  param(
    [string]$RecordingName,
    [string]$ScenarioName,
    [string]$ConvertedDir,
    [string]$MoveToGlobalInitial,
    [string]$MoveToGlobalFinal,
    [string]$Pass2PriorityMoveToGlobalValue,
    [bool]$SkipConverterUsernameArg
  )
  if ([string]::IsNullOrWhiteSpace($ConvertedDir) -or -not (Test-Path $ConvertedDir)) { return @{} }

  $scenarioYamlPath = Join-Path $ConvertedDir "scenario.yaml"
  $scenarioDataPath = Join-Path $ConvertedDir "scenario-data.yaml"
  $repliesPaths = @(
    Get-ChildItem -Path $ConvertedDir -File -Filter "replies*.yaml" -ErrorAction SilentlyContinue |
    Select-Object -ExpandProperty FullName
  )

  $transactionStats = Get-ScenarioTransactionAnnotationStats -ScenarioYamlPath $scenarioYamlPath
  $annotationRows = Get-ScenarioDataAnnotationActualRows -ScenarioDataPath $scenarioDataPath -RepliesYamlPaths $repliesPaths

  $safeScenario = ConvertTo-SafeFileSegment -Value $ScenarioName
  $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
  $reportDir = Join-Path $ConversionReportsRoot $safeScenario
  New-Item -ItemType Directory -Path $reportDir -Force | Out-Null

  $htmlPath = Join-Path $reportDir "conversion-yaml-report-$safeScenario-$timestamp.html"

  $moveInitial = if ([string]::IsNullOrWhiteSpace($MoveToGlobalInitial)) { "<none>" } else { $MoveToGlobalInitial }
  $moveFinal = if ([string]::IsNullOrWhiteSpace($MoveToGlobalFinal)) { "<none>" } else { $MoveToGlobalFinal }
  $priorityMove = if ([string]::IsNullOrWhiteSpace($Pass2PriorityMoveToGlobalValue)) { "<none>" } else { $Pass2PriorityMoveToGlobalValue }
  $usernameArgMode = if ($SkipConverterUsernameArg) { "omitted" } else { "passed as -username `${username}" }

  $html = New-Object System.Collections.Generic.List[string]
  $enc = {
    param([string]$s)
    return [System.Net.WebUtility]::HtmlEncode([string]$s)
  }

  $html.Add("<!doctype html>") | Out-Null
  $html.Add("<html><head><meta charset='utf-8'><title>Conversion YAML Audit - $(& $enc $ScenarioName)</title>") | Out-Null
  $html.Add("<style>body{font-family:Segoe UI,Arial,sans-serif;margin:20px;color:#222}h1{margin:0 0 6px}h2{margin-top:24px}table{border-collapse:collapse;width:100%;margin-top:8px}th,td{border:1px solid #d0d7de;padding:6px 8px;text-align:left;font-size:13px}th{background:#f6f8fa}code{background:#f6f8fa;padding:1px 4px;border-radius:4px}.muted{color:#555}</style></head><body>") | Out-Null
  $html.Add("<h1>Conversion YAML Audit Report</h1>") | Out-Null
  $html.Add("<div class='muted'>Generated: $(& $enc (Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz'))</div>") | Out-Null

  $html.Add("<h2>Conversion Parameters</h2>") | Out-Null
  $html.Add("<table><thead><tr><th>Parameter</th><th>Value</th></tr></thead><tbody>") | Out-Null
  $paramRows = @(
    @{ K = "Recording"; V = $RecordingName },
    @{ K = "Scenario"; V = $ScenarioName },
    @{ K = "Host"; V = $HostName },
    @{ K = "User"; V = $UserName },
    @{ K = "Target Alias"; V = $TargetAlias },
    @{ K = "DB Env"; V = $DbEnv },
    @{ K = "Time Zone"; V = $TimeZone },
    @{ K = "Converter Username Arg"; V = $usernameArgMode },
    @{ K = "Initial move-to-global"; V = $moveInitial },
    @{ K = "Pass-2 priority move-to-global"; V = $priorityMove },
    @{ K = "Final move-to-global"; V = $moveFinal }
  )
  foreach ($row in $paramRows) {
    $html.Add("<tr><td>$(& $enc $row.K)</td><td><code>$(& $enc $row.V)</code></td></tr>") | Out-Null
  }
  $html.Add("</tbody></table>") | Out-Null

  $html.Add("<h2>Transaction Annotation Summary (scenario.yaml)</h2>") | Out-Null
  $html.Add("<table><thead><tr><th>Metric</th><th>Count</th></tr></thead><tbody>") | Out-Null
  $summaryRows = @(
    @{ K = "Total transactions"; V = [string]$transactionStats.TotalTransactions },
    @{ K = "Transactions containing annotations"; V = [string]$transactionStats.AnnotatedTransactions },
    @{ K = "Transactions without annotations"; V = [string]$transactionStats.UnannotatedTransactions },
    @{ K = "Total annotation tokens found"; V = [string]$transactionStats.TotalAnnotationTokens }
  )
  foreach ($row in $summaryRows) {
    $html.Add("<tr><td>$(& $enc $row.K)</td><td>$(& $enc $row.V)</td></tr>") | Out-Null
  }
  $html.Add("</tbody></table>") | Out-Null

  $html.Add("<h2>scenario-data.yaml Annotations and Resolved Values (from replies.yaml)</h2>") | Out-Null
  if ($annotationRows.Count -eq 0) {
    $html.Add("<div>No scenario-data annotations were found.</div>") | Out-Null
  } else {
    $html.Add("<table><thead><tr><th>transName</th><th>paramName</th><th>annotation</th><th>actualValue</th></tr></thead><tbody>") | Out-Null
    foreach ($r in $annotationRows) {
      $t = [string]$r.transName
      $p = [string]$r.paramName
      $a = [string]$r.annotation
      $av = [string]$r.actualValue
      $html.Add("<tr><td>$(& $enc $t)</td><td>$(& $enc $p)</td><td><code>$(& $enc $a)</code></td><td><code>$(& $enc $av)</code></td></tr>") | Out-Null
    }
    $html.Add("</tbody></table>") | Out-Null
  }
  $html.Add("</body></html>") | Out-Null

  Set-Content -Path $htmlPath -Value ($html -join "`r`n") -Encoding UTF8
  Write-Host "Generated conversion YAML audit report (HTML): $htmlPath"
  return @{
    HtmlPath = $htmlPath
    AnnotationRows = $annotationRows.Count
    TotalTransactions = $transactionStats.TotalTransactions
    AnnotatedTransactions = $transactionStats.AnnotatedTransactions
  }
}

Assert-CommandAvailable -Name "ssh"
Assert-CommandAvailable -Name "scp"
Assert-CommandAvailable -Name "tar"

Write-Host "Resolved DB environment for SQL identity lookup: $DbEnv"

if (-not (Test-Path $RecordingsRoot)) {
  throw "Recordings root does not exist: $RecordingsRoot"
}
if (-not (Test-Path $SqlFile)) {
  throw "SQL file does not exist: $SqlFile"
}

if ($RecordingNames.Count -eq 0) {
  $RecordingNames = (Get-ChildItem -Path $RecordingsRoot -Directory | Select-Object -ExpandProperty Name)
}
if ($RecordingNames.Count -eq 0) {
  throw "No recordings found to process."
}

$sqlText = Get-Content -Raw $SqlFile
$results = New-Object System.Collections.Generic.List[object]

Write-Host "Validating remote jars..."
Invoke-Ssh "ls -l /root/gatling/*.jar"

foreach ($recordingName in $RecordingNames) {
  $recordingDir = Join-Path $RecordingsRoot $recordingName
  if (-not (Test-Path $recordingDir)) {
    Write-Warning "Skipping missing recording folder: $recordingDir"
    continue
  }

  Write-Host ""
  Write-Host "============================="
  Write-Host "Processing recording: $recordingName"
  Write-Host "============================="

  $reference = Get-ReferenceScenarioFolder -RecordingName $recordingName
  $referenceName = if ($reference) { $reference.Name } else { $recordingName }
  $referenceScenarioData = if ($reference) { Join-Path $reference.FullName "scenario-data.yaml" } else { "" }

  $paramMap = if ($referenceScenarioData) { Get-FirstGlobalDataParamsMap -ScenarioDataPath $referenceScenarioData } else { [ordered]@{} }
  $referenceReplies = @()
  if ($reference) {
    $referenceReplies = @(Get-ChildItem -Path $reference.FullName -File -Filter "replies*.yaml" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)
  }
  $paramMap = Resolve-ParamMapDynamicValuesFromReplies -ParamMap $paramMap -RepliesYamlPaths $referenceReplies

  $sqlKeys = Get-SqlSectionKeys -SqlText $sqlText -ScenarioName $referenceName

  if ($sqlKeys.Count -eq 0 -and $paramMap.Count -gt 0) {
    foreach ($k in $paramMap.Keys) {
      if ($k -match '(?i)(user|username|person|prsnl|encntr|encounter|order|referral|fin|accession).*(id|num|name)?') {
        [void]$sqlKeys.Add($k)
      }
    }
  }

  $moveToGlobal = ""
  if (-not [string]::IsNullOrWhiteSpace($ProvidedMoveToGlobal)) {
    $moveToGlobal = $ProvidedMoveToGlobal.Trim()
    Write-Host "Using caller-provided --move-to-global exactly (auto-derive disabled for initial pass): $moveToGlobal"
  } else {
    $moveToGlobal = Get-MoveToGlobalString -OrderedKeys $sqlKeys -ParamMap $paramMap
  }
  $initialMoveToGlobal = $moveToGlobal
  if ([string]::IsNullOrWhiteSpace($moveToGlobal)) {
    Write-Host "No move-to-global pairs derived; conversion will continue without --move-to-global."
  } else {
    Write-Host "Initial --move-to-global pairs (pre pass-1): $moveToGlobal"
  }

  $usernameOverrideSource = if (-not [string]::IsNullOrWhiteSpace($ProvidedMoveToGlobal)) { $ProvidedMoveToGlobal } else { $Pass2PriorityMoveToGlobal }
  $skipConverterUsernameArg = Has-MultipleExplicitUsernames -PriorityMoveToGlobal $usernameOverrideSource
  if ($skipConverterUsernameArg) {
    Write-Host "Detected multiple explicit username overrides in pass-2 priority input; converter -username argument will be omitted."
  }

  # Pass 1 conversion.
  $downloadRoot = Convert-RecordingRemote -RecordingDir $recordingDir -MoveToGlobal $moveToGlobal -SkipConverterUsernameArg $skipConverterUsernameArg
  $convertedDir = Resolve-ConvertedScenarioDir -DownloadedRoot $downloadRoot

  # Derive identity values from pass-1 scenario-data and replies (authoritative source for dynamic values).
  $pass1ScenarioData = Join-Path $convertedDir "scenario-data.yaml"
  $pass1Replies = @(
    Get-ChildItem -Path $convertedDir -File -Filter "replies*.yaml" -ErrorAction SilentlyContinue |
    Select-Object -ExpandProperty FullName
  )
  $derivedMap = Get-IdentityMoveMapFromScenarioAndReplies -ScenarioDataPath $pass1ScenarioData -RepliesYamlPaths $pass1Replies

  $usernameForSqlLookup = Get-PreferredUsernameForLookup -DerivedIdentityMap $derivedMap -ParamMap $paramMap
  if (-not [string]::IsNullOrWhiteSpace($usernameForSqlLookup)) {
    if (-not $derivedMap.Contains("username")) {
      $derivedMap["username"] = $usernameForSqlLookup
    }
  } else {
    Write-Warning "No usable username found from pass-1 data; SQL user_id lookup will rely only on explicit pass-2 username_* values."
  }

  if (-not $SkipSecondPassRefinement) {
    Add-SqlUserIdsForAllUsernames -MoveMap $derivedMap -PriorityMoveToGlobal $Pass2PriorityMoveToGlobal -DbEnvironment $DbEnv -SqlplusScript $SqlplusScriptPath

    Apply-Pass2PriorityMoveToGlobal -MoveMap $derivedMap -PriorityMoveToGlobal $Pass2PriorityMoveToGlobal

    $refinedMoveToGlobal = Get-MoveToGlobalStringFromMap -MoveMap $derivedMap
    if (-not [string]::IsNullOrWhiteSpace($refinedMoveToGlobal)) {
      Write-Host "Refined --move-to-global pairs from pass-1 replies/scenario-data: $refinedMoveToGlobal"
      if ($refinedMoveToGlobal -ne $moveToGlobal) {
        if (Test-Path $downloadRoot) { Remove-Item -Recurse -Force -Path $downloadRoot -ErrorAction SilentlyContinue }
        # Pass 2 conversion with replies-derived values.
        $downloadRoot = Convert-RecordingRemote -RecordingDir $recordingDir -MoveToGlobal $refinedMoveToGlobal -SkipConverterUsernameArg $skipConverterUsernameArg
        $convertedDir = Resolve-ConvertedScenarioDir -DownloadedRoot $downloadRoot
        $moveToGlobal = $refinedMoveToGlobal
      } else {
        $moveToGlobal = $refinedMoveToGlobal
      }
    } else {
      Write-Warning "No pass-1 replies-derived identity values were found; keeping initial mapping."
    }
  } else {
    Write-Host "Skipping pass-2 refinement as requested. Keeping initial --move-to-global exactly as provided."
    if (-not [string]::IsNullOrWhiteSpace($ProvidedMoveToGlobal)) {
      $providedMap = Convert-MoveToGlobalStringToMap -MoveToGlobal $ProvidedMoveToGlobal
      foreach ($k in $providedMap.Keys) {
        $derivedMap[$k] = [string]$providedMap[$k]
      }
    }
  }
  Apply-UsernameAnnotationReplacements -ConvertedDir $convertedDir -MoveMap $derivedMap
  $conversionReport = Write-ConversionYamlReport `
    -RecordingName $recordingName `
    -ScenarioName $referenceName `
    -ConvertedDir $convertedDir `
    -MoveToGlobalInitial $initialMoveToGlobal `
    -MoveToGlobalFinal $moveToGlobal `
    -Pass2PriorityMoveToGlobalValue $Pass2PriorityMoveToGlobal `
    -SkipConverterUsernameArg:$skipConverterUsernameArg
  $scenarioNameForRunner = $referenceName
  $referenceDirPath = if ($reference) { $reference.FullName } else { "" }
  $runnerScenarioDir = Prepare-RunnerScenario -ScenarioName $scenarioNameForRunner -ConvertedDir $convertedDir -ReferenceDir $referenceDirPath -DerivedIdentityMap $derivedMap

  $results.Add([pscustomobject]@{
    Recording = $recordingName
    Scenario  = $scenarioNameForRunner
    Converted = $convertedDir
    RunnerDir = $runnerScenarioDir
    MovePairs = $moveToGlobal
    ConversionReport = if ($conversionReport) { [string]$conversionReport["HtmlPath"] } else { "" }
  }) | Out-Null
}

if ($results.Count -eq 0) {
  throw "No recordings were processed."
}

Write-Host ""
Write-Host "Generated scenarios:"
$results | ForEach-Object {
  Write-Host " - $($_.Scenario) <= $($_.Recording)"
  if (-not [string]::IsNullOrWhiteSpace([string]$_.ConversionReport)) {
    Write-Host "   conversion report: $($_.ConversionReport)"
  }
}

if (-not $SkipGatlingRun) {
  $runnerScript = Join-Path $RunnerScriptsRoot "run_gatling_remote.ps1"
  if (-not (Test-Path $runnerScript)) {
    throw "gatling-runner script not found at: $runnerScript"
  }

  foreach ($row in $results) {
    Write-Host ""
    Write-Host "Running gatling-runner for scenario: $($row.Scenario)"
    & pwsh -NoProfile -Command "& '$runnerScript' -ScenarioName '$($row.Scenario)' -TargetAlias '$TargetAlias'"
    if ($LASTEXITCODE -ne 0) {
      throw "gatling-runner failed for scenario: $($row.Scenario)"
    }
  }
}

Write-Host ""
Write-Host "Completed."
