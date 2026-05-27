param(
  [Parameter(Mandatory=$true)][string]$ScenarioName,
  [string]$TargetAlias,
  [string]$HostName = "10.191.200.22",
  [string]$UserName = "root",
  [string]$Password = $env:GATLING_SSH_PASSWORD,
  [string]$KeyPath,
  [string]$LocalScriptRoot = "C:/Users/prakash/Desktop/project/NBS/gatling/script",
  [string]$LocalReportsDir = "C:/Users/prakash/Desktop/project/NBS/gatling/reports",
  [string]$RemoteBaseDir = "/root/gatling",
  [string]$RemoteRunDirName = "testrun",
  [string]$RemoteReportDirName = "report",
  [string]$ReplacementFrom = "MillDomain",
  [string]$ReplacementTo = "ablfhir",
  [string]$ForcedAuthority = "ablfhir",
  [string]$ForcedConfigPassword = "c0630system",
  [string]$ForcedScenarioDataPassword = "scale",
  [bool]$VerboseLogging = $true,
  [int]$StartUsers = 1,
  [int]$EndUsers = 1,
  [int]$DurationSeconds = 1,
  [int]$RampDurationSeconds = 0,
  [string]$ReportOnlyOutPath,
  [int]$ExecutionTimeoutSeconds = 7200
)

$ErrorActionPreference = "Stop"
$reportOnlyMode = -not [string]::IsNullOrWhiteSpace($ReportOnlyOutPath)

# Compatibility shim: some launcher contexts can swap these two named args.
if (
  -not [string]::IsNullOrWhiteSpace($TargetAlias) -and
  -not [string]::IsNullOrWhiteSpace($ScenarioName) -and
  $ScenarioName -ieq "ablfhir" -and
  $TargetAlias -ine "ablfhir"
) {
  $tmp = $ScenarioName
  $ScenarioName = $TargetAlias
  $TargetAlias = $tmp
}

if (-not [string]::IsNullOrWhiteSpace($TargetAlias)) {
  if ($TargetAlias -ieq "ablfhir") {
    if (-not $PSBoundParameters.ContainsKey("HostName")) { $HostName = "10.191.200.22" }
    if (-not $PSBoundParameters.ContainsKey("UserName")) { $UserName = "root" }
    if (-not $PSBoundParameters.ContainsKey("KeyPath")) { $KeyPath = "C:/Users/prakash/.ssh/id_gatling" }
  } else {
    throw "Unknown TargetAlias '$TargetAlias'. Supported aliases: ablfhir"
  }
}

$usingKey = -not [string]::IsNullOrWhiteSpace($KeyPath)
$usingPassword = -not [string]::IsNullOrWhiteSpace($Password)

if (-not $reportOnlyMode) {
  if (-not $usingKey -and -not $usingPassword) {
    throw "Provide either -KeyPath or -Password (or set GATLING_SSH_PASSWORD)."
  }

  if ($usingKey -and $usingPassword) {
    throw "Use only one auth mode: -KeyPath or -Password."
  }

  if ($usingKey -and -not (Test-Path $KeyPath)) {
    throw "SSH key file not found: $KeyPath"
  }

  if (-not $usingKey) {
    if (-not (Get-Module -ListAvailable -Name Posh-SSH)) {
      throw "Posh-SSH module is required for password mode. Install with: Install-Module Posh-SSH -Scope CurrentUser"
    }
    Import-Module Posh-SSH -ErrorAction Stop
  }
}

$scenarioDir = Join-Path $LocalScriptRoot $ScenarioName
$configPath = Join-Path $scenarioDir "config.yaml"
$scenarioPath = Join-Path $scenarioDir "scenario.yaml"
$scenarioDataPath = Join-Path $scenarioDir "scenario-data.yaml"

$requiredFiles = @($configPath, $scenarioPath, $scenarioDataPath)
$missing = $requiredFiles | Where-Object { -not (Test-Path $_) }
if ($missing.Count -gt 0) {
  throw "Missing required files: $($missing -join ', ')"
}

New-Item -ItemType Directory -Path $LocalReportsDir -Force | Out-Null
$scenarioReportDir = Join-Path $LocalReportsDir $ScenarioName
New-Item -ItemType Directory -Path $scenarioReportDir -Force | Out-Null
$runTimestamp = Get-Date -Format "yyyyMMdd-HHmmss"

function Set-OrAppend-YamlScalar {
  param(
    [Parameter(Mandatory=$true)][string]$Content,
    [Parameter(Mandatory=$true)][string]$Key,
    [Parameter(Mandatory=$true)][string]$Value
  )

  $keyPattern = '(?m)^(\s*' + [regex]::Escape($Key) + '\s*:\s*).*$'
  if ([regex]::IsMatch($Content, $keyPattern)) {
    return [regex]::Replace($Content, $keyPattern, '${1}' + $Value)
  }

  return $Content.TrimEnd() + "`r`n$Key`: $Value`r`n"
}

function Set-ScenarioDataGlobalParam {
  param(
    [Parameter(Mandatory=$true)][string]$Content,
    [Parameter(Mandatory=$true)][string]$ParamName,
    [Parameter(Mandatory=$true)][string]$ParamValue
  )

  # Remove invalid top-level scalars that break ScenarioData parsing.
  $Content = [regex]::Replace($Content, '(?m)^(authority|username|password)\s*:\s*.*\r?\n', '')

  # Ensure globalDataSets block exists.
  if ($Content -notmatch '(?m)^globalDataSets:') {
    $Content = $Content.TrimEnd() + "`r`nglobalDataSets:`r`n- queryString: `"`"`r`n  params:`r`n  headers: null`r`n"
  }
  if ($Content -notmatch '(?m)^scenarioDataSets:') {
    $Content = $Content.TrimEnd() + "`r`nscenarioDataSets: null`r`n"
  }

  $gStart = $Content.IndexOf("globalDataSets:")
  if ($gStart -lt 0) { return $Content }
  $tail = $Content.Substring($gStart)
  $gEndMarker = $tail.IndexOf("scenarioDataSets:")
  $globalBlock = if ($gEndMarker -gt 0) { $tail.Substring(0, $gEndMarker) } else { $tail }

  $namePattern = '(?m)^\s*-\s*name:\s*"?'+[regex]::Escape($ParamName)+'"?\s*$'
  if ([regex]::IsMatch($globalBlock, $namePattern)) {
    $pairPattern = '(?ms)(-\s+name:\s*"?'+[regex]::Escape($ParamName)+'"?\s*\r?\n\s+value:\s*"?)([^"\r\n]*)(\"?)'
    $Content = [regex]::Replace($Content, $pairPattern, '${1}' + $ParamValue + '$3')
    return $Content
  }

  $insert = "  - name: `"$ParamName`"`r`n    value: `"$ParamValue`"`r`n"
  $Content = [regex]::Replace($Content, '(?ms)(globalDataSets:\s*\r?\n-\s*queryString:\s*.*?\r?\n\s*params:\s*\r?\n)', '$1' + $insert, 1)
  return $Content
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("gatling-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

try {
  $localOutPath = $null
  if (-not $reportOnlyMode) {
    $tempConfig = Join-Path $tempRoot "config.yaml"
    $tempScenario = Join-Path $tempRoot "scenario.yaml"
    $tempScenarioData = Join-Path $tempRoot "scenario-data.yaml"

    $configContent = (Get-Content -Path $configPath -Raw).Replace($ReplacementFrom, $ReplacementTo)
    $configContent = [regex]::Replace($configContent, '(?m)^(\s*verboseLogging\s*:\s*).*$' , ('${1}' + $VerboseLogging.ToString().ToLowerInvariant()))
    if ($configContent -notmatch '(?m)^\s*verboseLogging\s*:') {
      $configContent = $configContent.TrimEnd() + "`r`nverboseLogging: $($VerboseLogging.ToString().ToLowerInvariant())`r`n"
    }
    $configContent = Set-OrAppend-YamlScalar -Content $configContent -Key "authority" -Value $ForcedAuthority
    $configContent = Set-OrAppend-YamlScalar -Content $configContent -Key "password" -Value $ForcedConfigPassword
    $configContent | Set-Content -Path $tempConfig -Encoding UTF8

    $scenarioContent = Get-Content -Path $scenarioPath -Raw
    $scenarioContent = [regex]::Replace($scenarioContent, '(?m)^(\s*userTimeUnit\s*:\s*).*$' , '${1}"second"')
    $scenarioContent = [regex]::Replace($scenarioContent, '(?m)^(\s*durationSeconds\s*:\s*).*$', ('${1}' + $DurationSeconds))
    $scenarioContent = [regex]::Replace($scenarioContent, '(?m)^(\s*rampDurationSeconds\s*:\s*).*$', ('${1}' + $RampDurationSeconds))
    $scenarioContent = [regex]::Replace($scenarioContent, '(?m)^(\s*startUsers\s*:\s*).*$', ('${1}' + $StartUsers))
    $scenarioContent = [regex]::Replace($scenarioContent, '(?m)^(\s*endUsers\s*:\s*).*$', ('${1}' + $EndUsers))

    if ($scenarioContent -notmatch '(?m)^\s*userTimeUnit\s*:') {
      $scenarioContent = $scenarioContent.TrimEnd() + "`r`nuserTimeUnit: second`r`n"
    }
    if ($scenarioContent -notmatch '(?m)^\s*durationSeconds\s*:') {
      $scenarioContent = $scenarioContent.TrimEnd() + "`r`ndurationSeconds: $DurationSeconds`r`n"
    }
    if ($scenarioContent -notmatch '(?m)^\s*rampDurationSeconds\s*:') {
      $scenarioContent = $scenarioContent.TrimEnd() + "`r`nrampDurationSeconds: $RampDurationSeconds`r`n"
    }
    if ($scenarioContent -notmatch '(?m)^\s*startUsers\s*:') {
      $scenarioContent = $scenarioContent.TrimEnd() + "`r`nstartUsers: $StartUsers`r`n"
    }
    if ($scenarioContent -notmatch '(?m)^\s*endUsers\s*:') {
      $scenarioContent = $scenarioContent.TrimEnd() + "`r`nendUsers: $EndUsers`r`n"
    }

    $scenarioContent | Set-Content -Path $tempScenario -Encoding UTF8

    $scenarioDataContent = (Get-Content -Path $scenarioDataPath -Raw).Replace($ReplacementFrom, $ReplacementTo)
    $scenarioDataContent = Set-ScenarioDataGlobalParam -Content $scenarioDataContent -ParamName "authority" -ParamValue $ForcedAuthority
    $scenarioDataContent = Set-ScenarioDataGlobalParam -Content $scenarioDataContent -ParamName "password" -ParamValue $ForcedScenarioDataPassword
    $scenarioDataContent | Set-Content -Path $tempScenarioData -Encoding UTF8

    $remoteTempDirName = "templ-" + [guid]::NewGuid().ToString("N").Substring(0, 8)
    $remoteRunDir = "$RemoteBaseDir/$remoteTempDirName"
    $remoteOutFile = "$RemoteBaseDir/gatling.$remoteTempDirName.out"
    $localOutPath = Join-Path $tempRoot ("gatling.$RemoteRunDirName.out")
    $localUploadArchive = Join-Path $tempRoot "gatling-input-$remoteTempDirName.tar.gz"
    $remoteUploadArchive = "$remoteRunDir/input.tar.gz"

    & tar "-czf" $localUploadArchive "-C" $tempRoot "config.yaml" "scenario.yaml" "scenario-data.yaml"
    if ($LASTEXITCODE -ne 0) {
      throw "Failed to create local transfer archive: $localUploadArchive"
    }

    if ($usingKey) {
    $sshCommon = @("-o", "BatchMode=yes", "-o", "ConnectTimeout=15", "-o", "StrictHostKeyChecking=no", "-o", "UserKnownHostsFile=/dev/null", "-i", $KeyPath)
    $scpCommon = @("-o", "BatchMode=yes", "-o", "ConnectTimeout=15", "-o", "StrictHostKeyChecking=no", "-o", "UserKnownHostsFile=/dev/null", "-i", $KeyPath)
    $target = "$UserName@$HostName"

    $prepareCmd = "set -e; rm -rf '$remoteRunDir'; mkdir -p '$remoteRunDir'; mkdir -p '$RemoteBaseDir/$RemoteReportDirName'; rm -f '$remoteOutFile'"
    & ssh @sshCommon $target $prepareCmd
    if ($LASTEXITCODE -ne 0) { throw "Remote prepare step failed (key auth)." }

    & scp @scpCommon $localUploadArchive "$target`:$remoteUploadArchive"
    if ($LASTEXITCODE -ne 0) { throw "SCP upload failed for staged input archive." }
    & ssh @sshCommon $target "set -e; tar -xzf '$remoteUploadArchive' -C '$remoteRunDir'; rm -f '$remoteUploadArchive'"
    if ($LASTEXITCODE -ne 0) { throw "Remote extract failed for staged input archive." }

    $runCmd = "cd '$RemoteBaseDir' && bash -lc 'set -o pipefail; java -jar gatling-crank-executor.jar ./$remoteTempDirName ./$RemoteReportDirName false 0 2>&1 | tee gatling.$remoteTempDirName.out; exit `${PIPESTATUS[0]}'"
    Write-Host "Streaming remote Gatling console output..."
    & ssh @sshCommon $target $runCmd 2>&1 | ForEach-Object {
      if ($null -eq $_) { return }
      $text = [string]$_
      if ([string]::IsNullOrWhiteSpace($text)) { return }
      Write-Host $text
    }
    if ($LASTEXITCODE -ne 0) { Write-Warning "Remote Gatling command returned exit code $LASTEXITCODE. Continuing to parse output file." }

    & scp @scpCommon "$target`:$remoteOutFile" $localOutPath
    if ($LASTEXITCODE -ne 0) { throw "SCP download failed for $remoteOutFile" }

    $cleanupCmd = "rm -rf '$remoteRunDir'; rm -f '$remoteOutFile'"
    & ssh @sshCommon $target $cleanupCmd | Out-Null
  }
  else {
    $securePassword = ConvertTo-SecureString $Password -AsPlainText -Force
    $credential = New-Object System.Management.Automation.PSCredential($UserName, $securePassword)
    $session = New-SSHSession -ComputerName $HostName -Credential $credential -AcceptKey -ErrorAction Stop
    try {
      $prepareCmd = @(
        "set -e",
        "rm -rf '$remoteRunDir'",
        "mkdir -p '$remoteRunDir'",
        "mkdir -p '$RemoteBaseDir/$RemoteReportDirName'",
        "rm -f '$remoteOutFile'"
      ) -join "; "

      $prepareResult = Invoke-SSHCommand -SessionId $session.SessionId -Command $prepareCmd -TimeOut 120000
      if ($prepareResult.ExitStatus -ne 0) {
        throw "Remote prepare step failed: $($prepareResult.Error -join ' | ')"
      }

      Set-SCPItem -ComputerName $HostName -Credential $credential -AcceptKey -Path $localUploadArchive -Destination $remoteUploadArchive -ErrorAction Stop
      $extractResult = Invoke-SSHCommand -SessionId $session.SessionId -Command "set -e; tar -xzf '$remoteUploadArchive' -C '$remoteRunDir'; rm -f '$remoteUploadArchive'" -TimeOut 120000
      if ($extractResult.ExitStatus -ne 0) {
        throw "Remote extract step failed: $($extractResult.Error -join ' | ')"
      }

      $runCmd = "cd '$RemoteBaseDir' && java -jar gatling-crank-executor.jar ./$remoteTempDirName ./$RemoteReportDirName false 0 > gatling.$remoteTempDirName.out 2>&1"
      $runResult = Invoke-SSHCommand -SessionId $session.SessionId -Command $runCmd -TimeOut ($ExecutionTimeoutSeconds * 1000)
      if ($runResult.Output) {
        foreach ($line in $runResult.Output) {
          if ($null -eq $line) { continue }
          $text = [string]$line
          if ([string]::IsNullOrWhiteSpace($text)) { continue }
          Write-Host $text
        }
      }
      if ($runResult.ExitStatus -ne 0) {
        Write-Warning "Remote Gatling command returned exit code $($runResult.ExitStatus). Continuing to parse output file."
      }

      Get-SCPItem -ComputerName $HostName -Credential $credential -AcceptKey -Path $remoteOutFile -Destination $localOutPath -ErrorAction Stop
      $cleanupResult = Invoke-SSHCommand -SessionId $session.SessionId -Command "rm -rf '$remoteRunDir'; rm -f '$remoteOutFile'" -TimeOut 120000
      if ($cleanupResult.ExitStatus -ne 0) {
        Write-Warning "Remote cleanup reported non-zero exit: $($cleanupResult.ExitStatus)"
      }
    } finally {
      if ($session) {
        Remove-SSHSession -SessionId $session.SessionId | Out-Null
      }
    }
    }
  } else {
    if (-not (Test-Path -LiteralPath $ReportOnlyOutPath)) {
      throw "Report-only input .out file not found: $ReportOnlyOutPath"
    }
    $resolvedOut = Resolve-Path -LiteralPath $ReportOnlyOutPath
    $localOutPath = $resolvedOut.Path
    Write-Host "Report-only mode. Using existing .out file: $localOutPath"
  }

  $localRawCopyPath = Join-Path $scenarioReportDir ("$ScenarioName-$runTimestamp.out")
  Copy-Item -Path $localOutPath -Destination $localRawCopyPath -Force
  $lines = Get-Content -Path $localOutPath
  $reportLines = $lines | ForEach-Object { [regex]::Replace([string]$_, '\x1B\[[0-9;]*[A-Za-z]', '') }

  function Escape-Html {
    param([string]$Value)
    return [System.Net.WebUtility]::HtmlEncode([string]$Value)
  }

  function Truncate-Text {
    param(
      [string]$Value,
      [int]$MaxLength = 1800
    )

    if ([string]::IsNullOrEmpty($Value)) { return "" }
    if ($Value.Length -le $MaxLength) { return $Value }
    return $Value.Substring(0, $MaxLength) + "...(truncated)"
  }

  function Add-Range {
    param(
      [System.Collections.Generic.List[object]]$Ranges,
      [int]$Start,
      [int]$End,
      [int]$MaxIndex
    )

    if ($Start -lt 0) { $Start = 0 }
    if ($End -gt $MaxIndex) { $End = $MaxIndex }
    if ($End -lt $Start) { return }
    $Ranges.Add([PSCustomObject]@{ Start = $Start; End = $End })
  }

  function Merge-Ranges {
    param([object[]]$Ranges)

    if ($Ranges.Count -eq 0) { return @() }
    $normalized = @(
      $Ranges |
        Where-Object { $_ -ne $null -and $_.PSObject.Properties.Name -contains 'Start' -and $_.PSObject.Properties.Name -contains 'End' } |
        ForEach-Object {
          [PSCustomObject]@{
            Start = [int]$_.Start
            End = [int]$_.End
          }
        }
    )
    if ($normalized.Count -eq 0) { return @() }

    $sorted = $normalized | Sort-Object Start, End
    $merged = New-Object System.Collections.Generic.List[object]
    $current = [PSCustomObject]@{ Start = $sorted[0].Start; End = $sorted[0].End }

    for ($i = 1; $i -lt $sorted.Count; $i++) {
      $r = $sorted[$i]
      if ($r.Start -le ($current.End + 20)) {
        if ($r.End -gt $current.End) { $current.End = $r.End }
      } else {
        $merged.Add([PSCustomObject]@{ Start = $current.Start; End = $current.End })
        $current = [PSCustomObject]@{ Start = $r.Start; End = $r.End }
      }
    }

    $merged.Add([PSCustomObject]@{ Start = $current.Start; End = $current.End })
    return $merged.ToArray()
  }

  function Format-RangeBlock {
    param(
      [string[]]$AllLines,
      [int]$Start,
      [int]$End,
      [int]$MaxLines = 950
    )

    $s = [Math]::Max(0, $Start)
    $e = [Math]::Min($AllLines.Count - 1, $End)
    $isTruncated = $false
    if (($e - $s + 1) -gt $MaxLines) {
      $e = $s + $MaxLines - 1
      $isTruncated = $true
    }

    $formatted = for ($i = $s; $i -le $e; $i++) {
      "{0:D6}: {1}" -f ($i + 1), $AllLines[$i]
    }

    $text = ($formatted -join "`n")
    if ($isTruncated) {
      $text += "`n...(truncated; expand range in raw log for full section)"
    }

    return [PSCustomObject]@{
      StartLine = $s + 1
      EndLine = $e + 1
      Text = $text
    }
  }

  function Extract-JsonObjectFromString {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    $start = $Text.IndexOf('{')
    if ($start -lt 0) { return $null }

    $depth = 0
    $inString = $false
    $escaped = $false
    for ($i = $start; $i -lt $Text.Length; $i++) {
      $ch = $Text[$i]

      if ($escaped) {
        $escaped = $false
        continue
      }

      if ($ch -eq '\') {
        $escaped = $true
        continue
      }

      if ($ch -eq '"') {
        $inString = -not $inString
        continue
      }

      if (-not $inString) {
        if ($ch -eq '{') { $depth++ }
        elseif ($ch -eq '}') {
          $depth--
          if ($depth -eq 0) {
            return $Text.Substring($start, ($i - $start + 1))
          }
        }
      }
    }

    return $null
  }

  function Try-PrettyJson {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }

    $candidate = $Text.Trim()
    $candidate = $candidate -replace '&quot;', '"'
    $candidate = $candidate -replace '&amp;', '&'
    $candidate = $candidate -replace '\\r\\n', "`n"
    $candidate = $candidate -replace '\\n', "`n"

    $jsonOnly = Extract-JsonObjectFromString -Text $candidate
    if ([string]::IsNullOrWhiteSpace($jsonOnly)) { return $null }

    try {
      $obj = $jsonOnly | ConvertFrom-Json -ErrorAction Stop
      return ($obj | ConvertTo-Json -Depth 100)
    } catch {
      return $null
    }
  }

  function Try-PrettyJsonFromLineRange {
    param(
      [string[]]$AllLines,
      [int]$StartIndex,
      [int]$MaxLookaheadLines = 1200
    )

    if ($StartIndex -lt 0 -or $StartIndex -ge $AllLines.Count) { return $null }
    $firstLine = $AllLines[$StartIndex]
    $start = $firstLine.IndexOf('{')
    if ($start -lt 0) { return $null }

    $builder = New-Object System.Text.StringBuilder
    $depth = 0
    $inString = $false
    $escaped = $false
    $started = $false

    $last = [Math]::Min($AllLines.Count - 1, $StartIndex + $MaxLookaheadLines)
    for ($lineIndex = $StartIndex; $lineIndex -le $last; $lineIndex++) {
      $segment = if ($lineIndex -eq $StartIndex) { $AllLines[$lineIndex].Substring($start) } else { $AllLines[$lineIndex] }
      [void]$builder.AppendLine($segment)

      for ($k = 0; $k -lt $segment.Length; $k++) {
        $ch = $segment[$k]

        if ($escaped) {
          $escaped = $false
          continue
        }

        if ($ch -eq '\') {
          $escaped = $true
          continue
        }

        if ($ch -eq '"') {
          $inString = -not $inString
          continue
        }

        if (-not $inString) {
          if ($ch -eq '{') {
            $depth++
            $started = $true
          } elseif ($ch -eq '}') {
            $depth--
            if ($started -and $depth -eq 0) {
              return (Try-PrettyJson -Text $builder.ToString())
            }
          }
        }
      }
    }

    return $null
  }

  function Remove-CommonIndent {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) { return "" }
    $linesLocal = $Text -split "`r?`n"
    $nonEmpty = @($linesLocal | Where-Object { $_ -match '\S' })
    if ($nonEmpty.Count -eq 0) { return $Text.Trim() }

    $minIndent = [int]::MaxValue
    foreach ($ln in $nonEmpty) {
      $m = [regex]::Match($ln, '^\s*')
      if ($m.Success -and $m.Length -lt $minIndent) {
        $minIndent = $m.Length
      }
    }
    if ($minIndent -eq [int]::MaxValue) { $minIndent = 0 }

    $normalized = foreach ($ln in $linesLocal) {
      if ($ln.Length -ge $minIndent) { $ln.Substring($minIndent) } else { $ln.TrimStart() }
    }
    return (($normalized -join "`n").Trim())
  }

  function Get-RepliesYamlStatusFromBody {
    param([string]$ReplyBody)

    if ([string]::IsNullOrWhiteSpace($ReplyBody)) { return "Unknown" }

    if ($ReplyBody -match '(?i)"success_ind"\s*:\s*"?0"?' -or
        $ReplyBody -match '(?i)"status"\s*:\s*"(F|0)"' -or
        $ReplyBody -match '(?i)"operationstatus"\s*:\s*"F"' -or
        $ReplyBody -match '(?i)"status_data"\s*:\s*\{[\s\S]*?"status"\s*:\s*"F"') {
      return "Failure in replies.yaml"
    }

    if ($ReplyBody -match '(?i)"success_ind"\s*:\s*"?1"?' -or
        $ReplyBody -match '(?i)"status"\s*:\s*"(S|Z|1)"' -or
        $ReplyBody -match '(?i)"operationstatus"\s*:\s*"S"') {
      return "Success in replies.yaml"
    }

    return "Unknown in replies.yaml"
  }

  function Resolve-RepliesYamlPaths {
    param([string]$ScenarioDirectory)

    if ([string]::IsNullOrWhiteSpace($ScenarioDirectory) -or -not (Test-Path $ScenarioDirectory)) { return @() }
    $candidates = @(
      Get-ChildItem -Path $ScenarioDirectory -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^(?i)replies.*\.yaml$' }
    )
    if ($candidates.Count -eq 0) { return @() }

    $preferred = @(
      $candidates |
        Where-Object { $_.FullName -match '(?i)[\\/](Results)[\\/].*' } |
        Sort-Object Name, LastWriteTime -Descending
    )
    if ($preferred.Count -gt 0) {
      return @($preferred.FullName)
    }

    return @(($candidates | Sort-Object Name, LastWriteTime -Descending).FullName)
  }

  function Parse-RepliesYamlTransactions {
    param([string[]]$RepliesYamlPaths)

    $map = @{}
    if ($null -eq $RepliesYamlPaths -or $RepliesYamlPaths.Count -eq 0) { return $map }

    foreach ($filePath in $RepliesYamlPaths) {
      if ([string]::IsNullOrWhiteSpace($filePath) -or -not (Test-Path $filePath)) { continue }
      $rawReplies = Get-Content -Path $filePath -Raw
      $pattern = '(?ms)^\s*-\s*transName:\s*"([^"]+)"\s*\r?\n\s*replyBody:\s*\|-\s*\r?\n(.*?)(?=^\s*-\s*transName:\s*"|\z)'
      $matchesReplies = [regex]::Matches($rawReplies, $pattern)
      foreach ($m in $matchesReplies) {
        $txName = $m.Groups[1].Value.Trim()
        if ([string]::IsNullOrWhiteSpace($txName)) { continue }
        if ($map.ContainsKey($txName)) { continue }

        $bodyRaw = Remove-CommonIndent -Text $m.Groups[2].Value
        $bodyPretty = Try-PrettyJson -Text $bodyRaw
        if ([string]::IsNullOrWhiteSpace($bodyPretty)) {
          $bodyPretty = $bodyRaw
        }

        $map[$txName] = [PSCustomObject]@{
          Status = Get-RepliesYamlStatusFromBody -ReplyBody $bodyRaw
          Body = $bodyPretty
          FileName = [System.IO.Path]::GetFileName($filePath)
          SourcePath = $filePath
        }
      }
    }

    return $map
  }

  function Get-TransactionHitIndexes {
    param(
      [string[]]$AllLines,
      [string]$Transaction
    )

    $hits = New-Object System.Collections.Generic.List[int]
    if ($AllLines.Count -eq 0 -or [string]::IsNullOrWhiteSpace($Transaction)) { return @($hits) }

    $txProbe = $Transaction.Trim()
    $isTruncated = $txProbe.EndsWith("...")
    if ($isTruncated) {
      $txProbe = $txProbe.Substring(0, [Math]::Max(0, $txProbe.Length - 3))
    }

    for ($i = 0; $i -lt $AllLines.Count; $i++) {
      $line = $AllLines[$i]
      $isMatch = $false
      if (-not $isTruncated) {
        $isMatch = ($line.IndexOf($txProbe, [System.StringComparison]::OrdinalIgnoreCase) -ge 0)
      } else {
        if ($line -match '(?i)\[([^\]]+)\]') {
          foreach ($m in [regex]::Matches($line, '(?i)\[([^\]]+)\]')) {
            $name = $m.Groups[1].Value
            if ($name.StartsWith($txProbe, [System.StringComparison]::OrdinalIgnoreCase)) {
              $isMatch = $true
              break
            }
          }
        }
        if (-not $isMatch) {
          $isMatch = ($line.IndexOf($txProbe, [System.StringComparison]::OrdinalIgnoreCase) -ge 0)
        }
      }

      if ($isMatch) {
        $null = $hits.Add($i)
      }
    }
    return @($hits)
  }

  function Resolve-RepliesEntryForTransaction {
    param(
      [hashtable]$RepliesMap,
      [string]$Transaction
    )

    if ($null -eq $RepliesMap -or [string]::IsNullOrWhiteSpace($Transaction)) { return $null }
    if ($RepliesMap.ContainsKey($Transaction)) { return $RepliesMap[$Transaction] }

    $txProbe = $Transaction.Trim()
    if ($txProbe.EndsWith("...")) {
      $prefix = $txProbe.Substring(0, [Math]::Max(0, $txProbe.Length - 3))
      foreach ($k in $RepliesMap.Keys) {
        if ($k.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
          return $RepliesMap[$k]
        }
      }
    }
    return $null
  }

  function Get-MissingTokenDependency {
    param(
      [object[]]$TransactionRows,
      [string[]]$AllLines,
      [int]$WindowStart,
      [int]$WindowEnd
    )

    $outcomes = @($TransactionRows | ForEach-Object { $_.Outcome })
    $combinedOutcome = ($outcomes -join " | ")
    if ($combinedOutcome -notmatch '(?i)Failed to build request') { return $null }

    $searchStart = if ($WindowStart -ge 0) { $WindowStart } else { 0 }
    $searchEnd = if ($WindowEnd -ge $searchStart) { [Math]::Min($AllLines.Count - 1, $WindowEnd + 80) } else { $AllLines.Count - 1 }

    $tokenExpr = $null
    $errorLine = $null
    for ($i = $searchStart; $i -le $searchEnd; $i++) {
      $line = $AllLines[$i]
      if ($line -match '(?i)Failed to build request' -and $line -match '(?i)does not exist in the stored response values') {
        $m = [regex]::Match($line, '\$\{([^}]+)\}')
        if ($m.Success) {
          $tokenExpr = $m.Groups[1].Value.Trim()
          $errorLine = $i + 1
          break
        }
      }
    }

    if ([string]::IsNullOrWhiteSpace($tokenExpr)) { return $null }
    $sourceTx = ($tokenExpr -split '\.')[0]
    if ([string]::IsNullOrWhiteSpace($sourceTx)) { return $null }

    return [PSCustomObject]@{
      TokenExpression = $tokenExpr
      SourceTransaction = $sourceTx
      ErrorLine = $errorLine
    }
  }

  function Resolve-JsonPathValueFromText {
    param(
      [string]$JsonText,
      [string]$PathExpression
    )

    if ([string]::IsNullOrWhiteSpace($JsonText) -or [string]::IsNullOrWhiteSpace($PathExpression)) { return $null }

    $obj = $null
    try {
      $obj = $JsonText | ConvertFrom-Json -ErrorAction Stop
    } catch {
      return $null
    }

    $current = $obj
    $segments = @($PathExpression -split '\.')
    foreach ($segment in $segments) {
      if ($null -eq $current) { return $null }

      $tokenMatches = [regex]::Matches($segment, '([^\[\]]+)|\[(\d+)\]')
      foreach ($tm in $tokenMatches) {
        if ($tm.Groups[1].Success) {
          $propName = $tm.Groups[1].Value
          if ($current -is [System.Collections.IDictionary]) {
            if (-not $current.Contains($propName)) { return $null }
            $current = $current[$propName]
          } else {
            $propMatch = $current.PSObject.Properties.Match($propName) | Select-Object -First 1
            if ($null -eq $propMatch) { return $null }
            $current = $propMatch.Value
          }
        } elseif ($tm.Groups[2].Success) {
          $idx = [int]$tm.Groups[2].Value
          if ($current -is [System.Array]) {
            if ($idx -lt 0 -or $idx -ge $current.Length) { return $null }
            $current = $current[$idx]
          } elseif ($current -is [System.Collections.IList]) {
            if ($idx -lt 0 -or $idx -ge $current.Count) { return $null }
            $current = $current[$idx]
          } else {
            return $null
          }
        }
      }
    }

    if ($null -eq $current) { return "null" }
    if ($current -is [string] -or $current -is [ValueType]) { return [string]$current }
    try {
      return ($current | ConvertTo-Json -Depth 50 -Compress)
    } catch {
      return [string]$current
    }
  }

  function Get-TransactionBaseName {
    param([string]$Transaction)

    if ([string]::IsNullOrWhiteSpace($Transaction)) { return $Transaction }
    $parts = $Transaction -split '_'
    $numericIndex = -1
    for ($i = 0; $i -lt $parts.Length; $i++) {
      if ($parts[$i] -match '^\d+$') {
        $numericIndex = $i
        break
      }
    }

    if ($numericIndex -gt 0) {
      return (($parts[0..($numericIndex - 1)]) -join '_')
    }

    return $Transaction
  }

  function Get-TransactionWindow {
    param(
      [string[]]$AllLines,
      [string]$Transaction,
      [int[]]$HintIndexes
    )

    if ($AllLines.Count -eq 0 -or [string]::IsNullOrWhiteSpace($Transaction)) { return $null }

    $txProbe = $Transaction.Trim()
    $isTruncatedTx = $txProbe.EndsWith("...")
    if ($isTruncatedTx) {
      $txProbe = $txProbe.Substring(0, [Math]::Max(0, $txProbe.Length - 3))
    }
    $txEsc = [regex]::Escape($txProbe)
    $strongStartIndexes = New-Object System.Collections.Generic.List[int]
    $weakStartIndexes = New-Object System.Collections.Generic.List[int]
    $startUserId = $null

    for ($i = 0; $i -lt $AllLines.Count; $i++) {
      $line = $AllLines[$i]
      if (-not $isTruncatedTx -and $line -match "(?i)\[\d+\]\s+\[$txEsc\]\s+replacing\s+\$\{") {
        $null = $strongStartIndexes.Add($i)
      } elseif ($isTruncatedTx -and $line -match "(?i)\[\d+\]\s+\[([^\]]+)\]\s+replacing\s+\$\{") {
        $candidateTx = $Matches[1]
        if ($candidateTx.StartsWith($txProbe, [System.StringComparison]::OrdinalIgnoreCase)) {
          $null = $strongStartIndexes.Add($i)
        }
      } elseif (-not $isTruncatedTx -and $line -match "(?i)\[$txEsc\]") {
        $null = $weakStartIndexes.Add($i)
      } elseif ($isTruncatedTx -and $line.IndexOf($txProbe, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
        $null = $weakStartIndexes.Add($i)
      }
    }

    $start = $null
    if ($strongStartIndexes.Count -gt 0) {
      $start = ($strongStartIndexes | Sort-Object | Select-Object -First 1)
    } elseif ($weakStartIndexes.Count -gt 0) {
      $start = ($weakStartIndexes | Sort-Object | Select-Object -First 1)
    } elseif ($HintIndexes.Count -gt 0) {
      $start = ($HintIndexes | Sort-Object | Select-Object -First 1)
    } else {
      return $null
    }

    if ($AllLines[[int]$start] -match '(?i)\[(\d+)\]\s+\[') {
      $startUserId = $Matches[1]
    }

    $nextTxStart = $null
    for ($j = [int]$start + 1; $j -lt $AllLines.Count; $j++) {
      if ($AllLines[$j] -match '(?i)\[(\d+)\]\s+\[([^\]]+)\]\s+replacing\s+\$\{') {
        $candidateUser = $Matches[1]
        $candidateTx = $Matches[2]
        # In highly interleaved runs, only use same user stream as hard boundary.
        if ($null -ne $startUserId -and $candidateUser -ne $startUserId) { continue }
        $sameTx = if ($isTruncatedTx) {
          $candidateTx.StartsWith($txProbe, [System.StringComparison]::OrdinalIgnoreCase)
        } else {
          $candidateTx -ieq $Transaction
        }
        if (-not $sameTx) {
          $nextTxStart = $j
          break
        }
      }
    }

    $hardCapEnd = [Math]::Min($AllLines.Count - 1, ([int]$start + 7000))
    $end = if ($null -ne $nextTxStart) { [Math]::Min($hardCapEnd, ($nextTxStart - 1)) } else { $hardCapEnd }

    # Guard against too-narrow windows in noisy/interleaved logs.
    if (($end - [int]$start) -lt 120) {
      $end = [Math]::Min($AllLines.Count - 1, ([int]$start + 1200))
    }

    return [PSCustomObject]@{
      Start = [int]$start
      End = [int]$end
      MarkerIndexes = @($strongStartIndexes)
    }
  }

  function Find-RequestJsonInWindow {
    param(
      [string[]]$AllLines,
      [int]$Start,
      [int]$End
    )

    if ($AllLines.Count -eq 0 -or $Start -lt 0 -or $End -lt $Start) { return $null }

    $requestSearchEnd = [Math]::Min($AllLines.Count - 1, $End + 80)
    for ($j = $Start; $j -le $requestSearchEnd; $j++) {
      if ($AllLines[$j] -match '(?i)final body:\s*\{') {
        $pretty = Try-PrettyJsonFromLineRange -AllLines $AllLines -StartIndex $j
        if (-not [string]::IsNullOrWhiteSpace($pretty)) {
          return [PSCustomObject]@{
            Line = $j + 1
            Json = $pretty
          }
        }
      }
    }

    return $null
  }

  function Find-ResponseJsonInWindow {
    param(
      [string[]]$AllLines,
      [int]$Start,
      [int]$End,
      [string]$ExpectedRequestName
    )

    if ($AllLines.Count -eq 0 -or $Start -lt 0 -or $End -lt $Start) { return $null }
    $reqEsc = if ([string]::IsNullOrWhiteSpace($ExpectedRequestName)) { $null } else { [regex]::Escape($ExpectedRequestName) }

    $responseSearchEnd = [Math]::Min($AllLines.Count - 1, $End + 2800)
    for ($j = $Start; $j -le $responseSearchEnd; $j++) {
      $line = $AllLines[$j]
      $payload = $null
      if ($line -match '(?i)Request failed, reply body:\s*(.+)$') {
        $payload = $Matches[1]
      } elseif ($line -match '(?i)Dumping body of reply for\s+.+?:\s*(.+)$') {
        $payload = $Matches[1]
      } elseif ($line -match '(?i)\breply body\b\s*[:=-]\s*(.+)$') {
        $payload = $Matches[1]
      } elseif ($line -match '(?i)SimulationProcessor\s*-\s*Body:\s*(\{.+)$') {
        $payload = $Matches[1]
      } else {
        continue
      }

      if (-not [string]::IsNullOrWhiteSpace($payload)) {
        $pretty = Try-PrettyJson -Text $payload
        if ([string]::IsNullOrWhiteSpace($pretty)) {
          $pretty = Try-PrettyJsonFromLineRange -AllLines $AllLines -StartIndex $j
        }
        if ([string]::IsNullOrWhiteSpace($pretty)) { continue }

        if (-not [string]::IsNullOrWhiteSpace($reqEsc)) {
          if ($pretty -notmatch "(?i)""requestName""\s*:\s*""$reqEsc""") { continue }
        }

        return [PSCustomObject]@{
          Line = $j + 1
          Json = $pretty
        }
      }
    }

    # Wide fallback for interleaved logs: search further from start and enforce requestName if available.
    if (-not [string]::IsNullOrWhiteSpace($reqEsc)) {
      $wideEnd = [Math]::Min($AllLines.Count - 1, $Start + 12000)
      for ($j = $Start; $j -le $wideEnd; $j++) {
        $line = $AllLines[$j]
        $payload = $null
        if ($line -match '(?i)SimulationProcessor\s*-\s*Body:\s*(\{.+)$') {
          $payload = $Matches[1]
        } elseif ($line -match '(?i)Dumping body of reply for\s+.+?:\s*(.+)$') {
          $payload = $Matches[1]
        }
        if ([string]::IsNullOrWhiteSpace($payload)) { continue }

        $pretty = Try-PrettyJson -Text $payload
        if ([string]::IsNullOrWhiteSpace($pretty)) {
          $pretty = Try-PrettyJsonFromLineRange -AllLines $AllLines -StartIndex $j
        }
        if ([string]::IsNullOrWhiteSpace($pretty)) { continue }
        if ($pretty -notmatch "(?i)""requestName""\s*:\s*""$reqEsc""") { continue }

        return [PSCustomObject]@{
          Line = $j + 1
          Json = $pretty
        }
      }
    }

    return $null
  }

  $summaryRows = New-Object System.Collections.Generic.List[object]
  $summaryKeySet = New-Object 'System.Collections.Generic.HashSet[string]'
  $allTransactionNames = New-Object 'System.Collections.Generic.HashSet[string]'

  function Add-SummaryRow {
    param(
      [System.Collections.Generic.List[object]]$Rows,
      [System.Collections.Generic.HashSet[string]]$KeySet,
      [string]$Transaction,
      [string]$Outcome,
      [string]$Source
    )

    if ([string]::IsNullOrWhiteSpace($Transaction)) { return }
    if ([string]::IsNullOrWhiteSpace($Outcome)) { return }

    $normalizedTx = $Transaction.Trim()
    $normalizedOutcome = $Outcome.Trim()
    $key = "$Source|$normalizedTx|$normalizedOutcome"
    if ($KeySet.Add($key)) {
      $Rows.Add([PSCustomObject]@{
        Transaction = $normalizedTx
        Outcome = $normalizedOutcome
        Source = $Source
      })
    }
  }

  function Get-TransactionRecommendation {
    param(
      [object[]]$TransactionRows,
      [object]$Detail
    )

    $outcomes = @($TransactionRows | ForEach-Object { $_.Outcome })
    $combinedOutcome = ($outcomes -join " | ")
    $matchedText = if ($Detail -and $Detail.MatchedLines) { ($Detail.MatchedLines -join "`n") } else { "" }
    $responseText = if ($Detail -and $Detail.ResponseJson -and $Detail.ResponseJson.Count -gt 0) { [string]$Detail.ResponseJson[0] } else { "" }

    if ($combinedOutcome -match '(?i)Failed to build request') {
      $dependencyMatch = [regex]::Match($matchedText, '(?is)Failed to build request.*?\$\{([^}]+)\}.*?does not exist in the stored response values')
      if (-not $dependencyMatch.Success) {
        $dependencyMatch = [regex]::Match($matchedText, '\$\{([^}]+)\}')
      }
      if ($dependencyMatch.Success) {
        return "Fix missing dependency value `${$($dependencyMatch.Groups[1].Value)}` before this step (seed prior transaction output or add guard/default handling)."
      }
      return "Request template failed before send; verify placeholder variables come from earlier responses and add null/exists checks in YAML extraction."
    }

    if ($responseText -match '(?i)"debug_error_message"\s*:\s*"([^"]*)"') {
      $msg = $Matches[1].Trim()
      if (-not [string]::IsNullOrWhiteSpace($msg)) {
        return "Service returned debug_error_message. Validate input payload and prerequisite data; server message: $msg"
      }
    }

    if ($responseText -match '(?i)"CCL_ERROR"|CCL_RUN_|Unexpected symbol found|Unexpected character found') {
      return "CCL/script execution error detected. Validate script inputs and environment-specific codes/data before retrying."
    }

    if ($combinedOutcome -match '(?i)\bKO\s*=\s*\d+') {
      if ($responseText -match '(?i)"status"\s*:\s*"0"|"status"\s*:\s*"F"') {
        return "Service returned failure status. Compare request/response in this section and validate required fields, domain data, and operation-specific permissions."
      }
      return "KO detected without explicit build error. Review transaction window and failure trace to confirm request payload values and downstream dependency order."
    }

    return "Review request/response and failure trace for this transaction; start with requestName/status_data and validate prerequisite transaction outputs."
  }

  # 1) KO list from request summary lines: > TxName (OK=.. KO=..)
  $inRequestsSection = $false
  foreach ($line in $reportLines) {
    if ($line -match '^\s*----\s+Requests\s+') {
      $inRequestsSection = $true
      continue
    }

    if ($inRequestsSection -and $line -match '^\s*----\s+' -and $line -notmatch '^\s*----\s+Requests\s+') {
      $inRequestsSection = $false
      continue
    }

    if (-not $inRequestsSection) { continue }

    $koMatch = [regex]::Match($line, '^\s*>\s*(.+?)\s+\(OK=\s*(\d+)\s+KO=\s*(\d+)\s*\)')
    if ($koMatch.Success) {
      $tx = $koMatch.Groups[1].Value.Trim()
      $ko = [int]$koMatch.Groups[3].Value
      if (-not [string]::IsNullOrWhiteSpace($tx) -and $tx -ne "Global") {
        [void]$allTransactionNames.Add($tx)
      }
      if ($ko -gt 0 -and $tx -ne "Global") {
        Add-SummaryRow -Rows $summaryRows -KeySet $summaryKeySet -Transaction $tx -Outcome "KO=$ko" -Source "KO"
      }
    }
  }

  # 2) Error list from "---- Errors ----" section
  $inErrorsSection = $false
  $errorEntryLines = New-Object System.Collections.Generic.List[string]
  $currentErrorEntry = New-Object System.Collections.Generic.List[string]

  function Flush-ErrorEntry {
    param(
      [System.Collections.Generic.List[string]]$Buffer,
      [System.Collections.Generic.List[string]]$Sink
    )
    if ($null -eq $Buffer -or $Buffer.Count -eq 0) { return }
    $Sink.Add((($Buffer.ToArray()) -join " ").Trim()) | Out-Null
    $Buffer.Clear()
  }

  foreach ($line in $reportLines) {
    if ($line -match '^\s*----\s+Errors\s+') {
      $inErrorsSection = $true
      continue
    }

    if ($inErrorsSection -and $line -match '^\s*----\s+') {
      Flush-ErrorEntry -Buffer $currentErrorEntry -Sink $errorEntryLines
      $inErrorsSection = $false
      continue
    }

    if (-not $inErrorsSection) { continue }

    if ($line -match '^\s*>\s*') {
      Flush-ErrorEntry -Buffer $currentErrorEntry -Sink $errorEntryLines
      $currentErrorEntry.Add(([regex]::Replace($line, '^\s*>\s*', '')).Trim()) | Out-Null
      continue
    }

    if ($currentErrorEntry.Count -gt 0) {
      $currentErrorEntry.Add($line.Trim()) | Out-Null
    }
  }
  Flush-ErrorEntry -Buffer $currentErrorEntry -Sink $errorEntryLines

  foreach ($entry in $errorEntryLines) {
    $flatEntry = [regex]::Replace([string]$entry, '\s+', ' ').Trim()
    # Gatling may wrap error rows across lines, so "count (percent)" can appear in the middle.
    # Example:
    #   "> TxName: Failed to bu      1 (0.76%)"
    #   "ild request: ..."
    # Normalize by removing the count token wherever it appears and stitching the message back together.
    $countAnywhereMatch = [regex]::Match(
      $flatEntry,
      '^(?<before>.*?)\s+(?<count>\d+)\s+\(\s*(?<percent>[\d.]+%)\s*\)\s*(?<after>.*)$'
    )
    if ($countAnywhereMatch.Success) {
      $content = ($countAnywhereMatch.Groups["before"].Value + " " + $countAnywhereMatch.Groups["after"].Value).Trim()
      $content = [regex]::Replace($content, '\s+', ' ').Trim()
    } else {
      $errorLineMatch = [regex]::Match($flatEntry, '^(?<content>.+?)\s+(?<count>\d+)\s+\(\s*(?<percent>[\d.]+%)\s*\)\s*$')
      if (-not $errorLineMatch.Success) { continue }
      $content = $errorLineMatch.Groups["content"].Value.Trim()
    }

    $tx = $null
    $msg = $null

    $splitMatch = [regex]::Match($content, '^([^:]+):\s*(.+)$')
    if ($splitMatch.Success) {
      $candidateTx = $splitMatch.Groups[1].Value.Trim()
      $candidateMsg = $splitMatch.Groups[2].Value.Trim()

      # Keep only real transaction-like names; skip assertion/check expressions such as status.find.in(...)
      if ($candidateTx -notmatch '[()]' -and $candidateTx -match '^[A-Za-z0-9_-]+$') {
        $tx = $candidateTx
        $msg = $candidateMsg
      }
    } else {
      continue
    }

    if ([string]::IsNullOrWhiteSpace($tx) -or [string]::IsNullOrWhiteSpace($msg)) {
      continue
    }

    if ($msg -match '(?i)failed to build request') {
      $msg = "Failed to build request"
    }

    Add-SummaryRow -Rows $summaryRows -KeySet $summaryKeySet -Transaction $tx -Outcome $msg -Source "ERROR"
  }

  $escapedScenario = Escape-Html $ScenarioName
  $escapedHost = Escape-Html $HostName
  $escapedRawLogPath = Escape-Html $localRawCopyPath
  $repliesYamlPaths = Resolve-RepliesYamlPaths -ScenarioDirectory $scenarioDir
  $repliesYamlMap = Parse-RepliesYamlTransactions -RepliesYamlPaths $repliesYamlPaths
  $repliesYamlPathDisplay = if ($repliesYamlPaths.Count -gt 0) { ($repliesYamlPaths -join "; ") } else { "Not found" }
  $escapedRepliesYamlPath = Escape-Html $repliesYamlPathDisplay
  $generatedAt = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss zzz")
  $totalTransactions = $allTransactionNames.Count

  # Build unique transaction order and link anchors
  $orderedTransactions = New-Object System.Collections.Generic.List[string]
  $seenTransactions = @{}
  foreach ($row in $summaryRows) {
    if (-not $seenTransactions.ContainsKey($row.Transaction)) {
      $seenTransactions[$row.Transaction] = $true
      $orderedTransactions.Add($row.Transaction)
    }
  }

  $anchorByTransaction = @{}
  $anchorCounter = @{}
  foreach ($tx in $orderedTransactions) {
    $baseAnchor = [regex]::Replace($tx.ToLowerInvariant(), '[^a-z0-9]+', '-').Trim('-')
    if ([string]::IsNullOrWhiteSpace($baseAnchor)) { $baseAnchor = "tx" }

    if ($anchorCounter.ContainsKey($baseAnchor)) {
      $anchorCounter[$baseAnchor]++
    } else {
      $anchorCounter[$baseAnchor] = 1
    }

    $anchor = $baseAnchor
    if ($anchorCounter[$baseAnchor] -gt 1) {
      $anchor = "$baseAnchor-$($anchorCounter[$baseAnchor])"
    }
    $anchorByTransaction[$tx] = $anchor
  }

  # Gather detail evidence per transaction with line-numbered blocks.
  $detailsByTransaction = @{}
  foreach ($tx in $orderedTransactions) {
    $matchedLineSet = New-Object 'System.Collections.Generic.HashSet[string]'
    $hitIndexes = New-Object System.Collections.Generic.List[int]
    $candidateRanges = New-Object System.Collections.Generic.List[object]
    $requestJsonSet = New-Object 'System.Collections.Generic.HashSet[string]'
    $responseJsonSet = New-Object 'System.Collections.Generic.HashSet[string]'

    $baseHits = Get-TransactionHitIndexes -AllLines $lines -Transaction $tx
    foreach ($idx in $baseHits) {
      $null = $hitIndexes.Add($idx)
      $null = $matchedLineSet.Add(("{0:D6}: {1}" -f ($idx + 1), (Truncate-Text -Value $lines[$idx].Trim() -MaxLength 2000)))
    }

    $window = Get-TransactionWindow -AllLines $lines -Transaction $tx -HintIndexes @($hitIndexes)
    $windowStart = $null
    $windowEnd = $null

    if ($window -ne $null) {
      $windowStart = [int]$window.Start
      $windowEnd = [int]$window.End
      Add-Range -Ranges $candidateRanges -Start $windowStart -End $windowEnd -MaxIndex ($lines.Count - 1)
    } elseif ($hitIndexes.Count -gt 0) {
      $windowStart = [Math]::Max(0, ($hitIndexes | Sort-Object | Select-Object -First 1) - 200)
      $windowEnd = [Math]::Min($lines.Count - 1, $windowStart + 800)
      Add-Range -Ranges $candidateRanges -Start $windowStart -End $windowEnd -MaxIndex ($lines.Count - 1)
    }

    foreach ($hit in $hitIndexes) {
      # Keep a tiny local context list for fast visual orientation.
      $contextStart = [Math]::Max(0, $hit - 2)
      $contextEnd = [Math]::Min($lines.Count - 1, $hit + 2)
      for ($j = $contextStart; $j -le $contextEnd; $j++) {
        $null = $matchedLineSet.Add(("{0:D6}: {1}" -f ($j + 1), (Truncate-Text -Value $lines[$j].Trim() -MaxLength 2000)))
      }
    }

    if ($windowStart -ne $null -and $windowEnd -ne $null) {
      # Capture explicit failure traces near the transaction window.
      $failureAnchor = $null
      $failureSearchEnd = [Math]::Min($lines.Count - 1, $windowEnd + 350)
      for ($j = $windowStart; $j -le $failureSearchEnd; $j++) {
        if ($lines[$j] -match '(?i)(Request failed, reply body|Failed to build request|had the status:\s*F|GeneralDomainCallException)') {
          $failureAnchor = $j
          break
        }
      }
      if ($failureAnchor -ne $null) {
        Add-Range -Ranges $candidateRanges -Start ($failureAnchor - 40) -End ($failureAnchor + 220) -MaxIndex ($lines.Count - 1)
      }
    }

    # Extract request/response from transaction window first.
    $anchoredRequest = if ($windowStart -ne $null -and $windowEnd -ne $null) {
      Find-RequestJsonInWindow -AllLines $lines -Start $windowStart -End $windowEnd
    } else { $null }
    $expectedReqName = $null
    if ($anchoredRequest -ne $null -and $anchoredRequest.Json -match '(?i)"requestName"\s*:\s*"([^"]+)"') {
      $expectedReqName = $Matches[1]
      $requestJsonSet.Clear()
      $null = $requestJsonSet.Add($anchoredRequest.Json)
    }

    $anchoredResponse = if ($windowStart -ne $null -and $windowEnd -ne $null) {
      Find-ResponseJsonInWindow -AllLines $lines -Start $windowStart -End $windowEnd -ExpectedRequestName $expectedReqName
    } else { $null }
    if ($anchoredResponse -ne $null) {
      $responseJsonSet.Clear()
      $null = $responseJsonSet.Add($anchoredResponse.Json)
    }

    $formattedBlocks = @()
    if ($windowStart -ne $null -and $windowEnd -ne $null) {
      $windowBlock = Format-RangeBlock -AllLines $lines -Start $windowStart -End $windowEnd -MaxLines 1500
      $formattedBlocks += [PSCustomObject]@{
        StartLine = $windowBlock.StartLine
        EndLine = $windowBlock.EndLine
        Text = $windowBlock.Text
        Title = "Transaction Window"
      }
    }

    # Add one separate failure-focused block when we can find a concrete error anchor outside the core window.
    $failureFocus = $null
    if ($windowStart -ne $null -and $windowEnd -ne $null) {
      $failureSearchEnd = [Math]::Min($lines.Count - 1, $windowEnd + 350)
      for ($j = $windowStart; $j -le $failureSearchEnd; $j++) {
        if ($lines[$j] -match '(?i)(Request failed, reply body|Failed to build request|had the status:\s*F|GeneralDomainCallException)') {
          $failureFocus = $j
          break
        }
      }
    }

    if ($failureFocus -ne $null) {
      $failureStart = [Math]::Max(0, $failureFocus - 40)
      $failureEnd = [Math]::Min($lines.Count - 1, $failureFocus + 220)
      $insideWindow = ($windowStart -ne $null -and $windowEnd -ne $null -and $failureStart -ge $windowStart -and $failureEnd -le $windowEnd)
      if (-not $insideWindow) {
        $failureBlock = Format-RangeBlock -AllLines $lines -Start $failureStart -End $failureEnd -MaxLines 1200
        $formattedBlocks += [PSCustomObject]@{
          StartLine = $failureBlock.StartLine
          EndLine = $failureBlock.EndLine
          Text = $failureBlock.Text
          Title = "Failure Trace"
        }
      }
    }

    if ($formattedBlocks.Count -eq 0) {
      $mergedRanges = Merge-Ranges -Ranges ($candidateRanges.ToArray())
      foreach ($range in ($mergedRanges | Select-Object -First 1)) {
        $formatted = Format-RangeBlock -AllLines $lines -Start $range.Start -End $range.End -MaxLines 1200
        $formattedBlocks += [PSCustomObject]@{
          StartLine = $formatted.StartLine
          EndLine = $formatted.EndLine
          Text = $formatted.Text
          Title = "Detailed Log Block"
        }
      }
    }

    $txRowsForRecommendation = @($summaryRows | Where-Object { $_.Transaction -eq $tx })
    $tempDetailForRecommendation = [PSCustomObject]@{
      MatchedLines = @($matchedLineSet)
      ResponseJson = @($responseJsonSet)
    }
    $recommendation = Get-TransactionRecommendation -TransactionRows $txRowsForRecommendation -Detail $tempDetailForRecommendation

    # Dependency trace for "Failed to build request" errors.
    $windowStartArg = if ($windowStart -ne $null) { [int]$windowStart } else { -1 }
    $windowEndArg = if ($windowEnd -ne $null) { [int]$windowEnd } else { -1 }
    $missingTokenInfo = Get-MissingTokenDependency -TransactionRows $txRowsForRecommendation -AllLines $lines -WindowStart $windowStartArg -WindowEnd $windowEndArg
    $depSourceTx = $null
    $depTokenExpr = $null
    $depErrorLine = $null
    $depReqJson = $null
    $depReqLine = $null
    $depRespJson = $null
    $depRespLine = $null
    $depRepliesState = "Not found in replies*.yaml"
    $depRepliesFile = ""
    $depRepliesBody = ""
    $depTokenPathInReplies = ""
    $depTokenValueFromReplies = ""

    if ($missingTokenInfo -ne $null) {
      $depSourceTx = [string]$missingTokenInfo.SourceTransaction
      $depTokenExpr = [string]$missingTokenInfo.TokenExpression
      $depErrorLine = [int]$missingTokenInfo.ErrorLine

      $depHits = Get-TransactionHitIndexes -AllLines $lines -Transaction $depSourceTx
      if ($depHits.Count -gt 0) {
        $depWindow = Get-TransactionWindow -AllLines $lines -Transaction $depSourceTx -HintIndexes $depHits
        if ($depWindow -ne $null) {
          $depReq = Find-RequestJsonInWindow -AllLines $lines -Start ([int]$depWindow.Start) -End ([int]$depWindow.End)
          if ($depReq -ne $null) {
            $depReqJson = [string]$depReq.Json
            $depReqLine = [int]$depReq.Line
          }

          $depExpectedReqName = $null
          if ($depReqJson -and $depReqJson -match '(?i)"requestName"\s*:\s*"([^"]+)"') {
            $depExpectedReqName = $Matches[1]
          }
          $depResp = Find-ResponseJsonInWindow -AllLines $lines -Start ([int]$depWindow.Start) -End ([int]$depWindow.End) -ExpectedRequestName $depExpectedReqName
          if ($depResp -ne $null) {
            $depRespJson = [string]$depResp.Json
            $depRespLine = [int]$depResp.Line
          }
        }
      }

      if ($repliesYamlMap.ContainsKey($depSourceTx)) {
        $depRepliesState = [string]$repliesYamlMap[$depSourceTx].Status
        $depRepliesFile = [string]$repliesYamlMap[$depSourceTx].FileName
        $depRepliesBody = [string]$repliesYamlMap[$depSourceTx].Body
      }

      if (-not [string]::IsNullOrWhiteSpace($depTokenExpr) -and -not [string]::IsNullOrWhiteSpace($depSourceTx)) {
        if ($depTokenExpr.StartsWith($depSourceTx + ".", [System.StringComparison]::OrdinalIgnoreCase)) {
          $depTokenPathInReplies = $depTokenExpr.Substring($depSourceTx.Length + 1)
        } else {
          $depTokenPathInReplies = $depTokenExpr
        }
      }
      if (-not [string]::IsNullOrWhiteSpace($depTokenPathInReplies) -and -not [string]::IsNullOrWhiteSpace($depRepliesBody)) {
        $resolvedValue = Resolve-JsonPathValueFromText -JsonText $depRepliesBody -PathExpression $depTokenPathInReplies
        if (-not [string]::IsNullOrWhiteSpace([string]$resolvedValue)) {
          $depTokenValueFromReplies = [string]$resolvedValue
        }
      }
    }

    $repliesState = "Not found in replies*.yaml"
    $repliesFileName = ""
    $repliesBody = ""
    $repliesEntry = Resolve-RepliesEntryForTransaction -RepliesMap $repliesYamlMap -Transaction $tx
    if ($repliesEntry -ne $null) {
      $repliesState = [string]$repliesEntry.Status
      $repliesFileName = [string]$repliesEntry.FileName
      $repliesBody = [string]$repliesEntry.Body
    }

    $detailsByTransaction[$tx] = [PSCustomObject]@{
      MatchedLines = @($matchedLineSet)
      RangeBlocks = $formattedBlocks
      RequestJson = @($requestJsonSet)
      ResponseJson = @($responseJsonSet)
      RequestLine = if ($anchoredRequest -ne $null) { $anchoredRequest.Line } else { $null }
      ResponseLine = if ($anchoredResponse -ne $null) { $anchoredResponse.Line } else { $null }
      WindowStartLine = if ($windowStart -ne $null) { $windowStart + 1 } else { $null }
      WindowEndLine = if ($windowEnd -ne $null) { $windowEnd + 1 } else { $null }
      Recommendation = $recommendation
      RepliesYamlState = $repliesState
      RepliesYamlFileName = $repliesFileName
      RepliesYamlBody = $repliesBody
      MissingTokenExpression = $depTokenExpr
      MissingTokenErrorLine = $depErrorLine
      DependencySourceTransaction = $depSourceTx
      DependencyRequestJson = $depReqJson
      DependencyRequestLine = $depReqLine
      DependencyResponseJson = $depRespJson
      DependencyResponseLine = $depRespLine
      DependencyRepliesYamlState = $depRepliesState
      DependencyRepliesYamlFileName = $depRepliesFile
      DependencyRepliesYamlBody = $depRepliesBody
      DependencyTokenPathInReplies = $depTokenPathInReplies
      DependencyTokenValueFromReplies = $depTokenValueFromReplies
    }
  }

  $summaryTableRows = if ($summaryRows.Count -eq 0) {
    "<tr><td colspan='4'>No failed transactions were detected in KO or Errors sections.</td></tr>"
  } else {
    ($summaryRows | ForEach-Object {
      $txEsc = Escape-Html $_.Transaction
      $outEsc = Escape-Html $_.Outcome
      $anchor = $anchorByTransaction[$_.Transaction]
      $rec = ""
      $repState = "Not found in replies*.yaml"
      $repFile = ""
      if ($detailsByTransaction.ContainsKey($_.Transaction)) {
        $rec = [string]$detailsByTransaction[$_.Transaction].Recommendation
        $repState = [string]$detailsByTransaction[$_.Transaction].RepliesYamlState
        $repFile = [string]$detailsByTransaction[$_.Transaction].RepliesYamlFileName
      }
      $recEsc = Escape-Html $rec
      $tokenVal = if ($detailsByTransaction.ContainsKey($_.Transaction)) { [string]$detailsByTransaction[$_.Transaction].DependencyTokenValueFromReplies } else { "" }
      if (-not [string]::IsNullOrWhiteSpace($tokenVal)) {
        $tokenVal = Truncate-Text -Value $tokenVal -MaxLength 160
      }
      $repDisplay = if ([string]::IsNullOrWhiteSpace($repFile)) { $repState } else { "$repState ($repFile)" }
      if (-not [string]::IsNullOrWhiteSpace($tokenVal)) {
        $repDisplay = "$repDisplay | tokenValue=$tokenVal"
      }
      $repEsc = Escape-Html $repDisplay
      "<tr><td><a href='#$anchor'>$txEsc</a></td><td><pre>$outEsc</pre></td><td><pre>$repEsc</pre></td><td><pre>$recEsc</pre></td></tr>"
    }) -join "`n"
  }

  function Get-FailureType {
    param(
      [object]$Row,
      [object]$Detail
    )

    if ($null -ne $Row -and [string]$Row.Source -eq "KO") {
      return "KO"
    }

    $outcome = if ($null -ne $Row) { [string]$Row.Outcome } else { "" }
    if ($outcome -match '(?i)failed to build request') {
      return "Failed to build request"
    }

    $repliesState = if ($null -ne $Detail) { [string]$Detail.RepliesYamlState } else { "" }
    if ($repliesState -match '(?i)failure in replies\.yaml') {
      return "Failure in replies.yaml"
    }

    return "Other Error"
  }

  $failureTypeCounts = @{}
  foreach ($row in $summaryRows) {
    $detail = if ($detailsByTransaction.ContainsKey($row.Transaction)) { $detailsByTransaction[$row.Transaction] } else { $null }
    $failureType = Get-FailureType -Row $row -Detail $detail
    if ($failureTypeCounts.ContainsKey($failureType)) {
      $failureTypeCounts[$failureType]++
    } else {
      $failureTypeCounts[$failureType] = 1
    }
  }

  $failureTypeSummaryHtml = if ($summaryRows.Count -eq 0) {
    "<p>No failed transactions found.</p>"
  } else {
    $priority = @("KO", "Failed to build request", "Failure in replies.yaml", "Other Error")
    $orderedKeys = New-Object System.Collections.Generic.List[string]
    foreach ($k in $priority) {
      if ($failureTypeCounts.ContainsKey($k)) {
        $orderedKeys.Add($k) | Out-Null
      }
    }
    foreach ($k in ($failureTypeCounts.Keys | Sort-Object)) {
      if (-not $orderedKeys.Contains($k)) {
        $orderedKeys.Add($k) | Out-Null
      }
    }
    (
      "<ul>" +
      (($orderedKeys | ForEach-Object {
        $kEsc = Escape-Html $_
        $v = [int]$failureTypeCounts[$_]
        "<li><strong>${kEsc}:</strong> $v</li>"
      }) -join "") +
      "</ul>"
    )
  }

  $detailSections = if ($orderedTransactions.Count -eq 0) {
    "<p>No transaction-level details available.</p>"
  } else {
    ($orderedTransactions | ForEach-Object {
      $tx = $_
      $anchor = $anchorByTransaction[$tx]
      $detail = $detailsByTransaction[$tx]
      $txRows = $summaryRows | Where-Object { $_.Transaction -eq $tx }
      $summaryLine = ($txRows | ForEach-Object { "$($_.Source): $($_.Outcome)" }) -join " | "
      $summaryEsc = Escape-Html $summaryLine
      $recommendationEsc = Escape-Html ([string]$detail.Recommendation)
      $repliesStateEsc = Escape-Html ([string]$detail.RepliesYamlState)
      $repliesFileEsc = Escape-Html ([string]$detail.RepliesYamlFileName)
      $windowSummary = if ($detail.WindowStartLine -and $detail.WindowEndLine) {
        "Lines $($detail.WindowStartLine)-$($detail.WindowEndLine)"
      } else {
        "Not detected"
      }
      $windowSummaryEsc = Escape-Html $windowSummary

      $matchedHtml = if ($detail.MatchedLines.Count -eq 0) {
        "<li>No direct transaction lines found in output.</li>"
      } else {
        ($detail.MatchedLines | Select-Object -First 12 | ForEach-Object {
          "<li><pre>$(Escape-Html $_)</pre></li>"
        }) -join ""
      }

      $rangeBlockHtml = if ($detail.RangeBlocks.Count -eq 0) {
        "<li>No expanded log block captured for this transaction. Check raw log: $escapedRawLogPath</li>"
      } else {
        ($detail.RangeBlocks | ForEach-Object {
          $rangeTitle = if ($_.PSObject.Properties.Name -contains 'Title') { $_.Title } else { "Detailed Log Block" }
          $rangeLabel = "${rangeTitle}: Lines $($_.StartLine)-$($_.EndLine)"
          "<li><details><summary>$rangeLabel</summary><pre>$(Escape-Html $_.Text)</pre></details></li>"
        }) -join ""
      }

      $requestJsonHtml = if ($detail.RequestJson.Count -eq 0) {
        "<p>No parseable request JSON found in log for this transaction (with substituted runtime values).</p>"
      } else {
        ($detail.RequestJson | Select-Object -First 1 | ForEach-Object {
          $lineHint = if ($detail.RequestLine) { " (from line $($detail.RequestLine))" } else { "" }
          "<details><summary>Expand Request JSON$lineHint</summary><pre>$(Escape-Html $_)</pre></details>"
        }) -join ""
      }

      $responseJsonHtml = if ($detail.ResponseJson.Count -eq 0) {
        "<p>No parseable response JSON found in log for this transaction.</p>"
      } else {
        ($detail.ResponseJson | Select-Object -First 1 | ForEach-Object {
          $lineHint = if ($detail.ResponseLine) { " (from line $($detail.ResponseLine))" } else { "" }
          "<details><summary>Expand Response JSON$lineHint</summary><pre>$(Escape-Html $_)</pre></details>"
        }) -join ""
      }

      $repliesBodyHtml = if ([string]::IsNullOrWhiteSpace([string]$detail.RepliesYamlBody)) {
        "<p>Transaction not found in replies.yaml.</p>"
      } else {
        "<details><summary>Expand replies.yaml Response Body</summary><pre>$(Escape-Html ([string]$detail.RepliesYamlBody))</pre></details>"
      }

      $dependencySectionHtml = if ([string]::IsNullOrWhiteSpace([string]$detail.DependencySourceTransaction)) {
        ""
      } else {
        $depTxEsc = Escape-Html ([string]$detail.DependencySourceTransaction)
        $depTokenEsc = Escape-Html ([string]$detail.MissingTokenExpression)
        $depErrLineEsc = Escape-Html ([string]$detail.MissingTokenErrorLine)
        $depReqHtml = if ([string]::IsNullOrWhiteSpace([string]$detail.DependencyRequestJson)) {
          "<p>No parseable dependency request JSON found for $depTxEsc in log.</p>"
        } else {
          $lineHint = if ($detail.DependencyRequestLine) { " (from line $($detail.DependencyRequestLine))" } else { "" }
          "<details><summary>Expand Dependency Request JSON$lineHint</summary><pre>$(Escape-Html ([string]$detail.DependencyRequestJson))</pre></details>"
        }
        $depRespHtml = if ([string]::IsNullOrWhiteSpace([string]$detail.DependencyResponseJson)) {
          "<p>No parseable dependency response JSON found for $depTxEsc in log.</p>"
        } else {
          $lineHint = if ($detail.DependencyResponseLine) { " (from line $($detail.DependencyResponseLine))" } else { "" }
          "<details><summary>Expand Dependency Response JSON$lineHint</summary><pre>$(Escape-Html ([string]$detail.DependencyResponseJson))</pre></details>"
        }
        $depRepStateEsc = Escape-Html ([string]$detail.DependencyRepliesYamlState)
        $depRepFileEsc = Escape-Html ([string]$detail.DependencyRepliesYamlFileName)
        $depTokenPathEsc = Escape-Html ([string]$detail.DependencyTokenPathInReplies)
        $depTokenValueEsc = Escape-Html ([string]$detail.DependencyTokenValueFromReplies)
        $depRepBodyHtml = if ([string]::IsNullOrWhiteSpace([string]$detail.DependencyRepliesYamlBody)) {
          "<p>Dependency transaction not found in replies*.yaml.</p>"
        } else {
          "<details><summary>Expand Dependency replies.yaml Response Body</summary><pre>$(Escape-Html ([string]$detail.DependencyRepliesYamlBody))</pre></details>"
        }
@"
  <h4>Missing Token Dependency</h4>
  <div class='tx-summary'><strong>Missing Token:</strong> $depTokenEsc</div>
  <div class='tx-summary'><strong>Error Line:</strong> $depErrLineEsc</div>
  <div class='tx-summary'><strong>Source Transaction:</strong> $depTxEsc</div>
  $depReqHtml
  $depRespHtml
  <div class='tx-summary'><strong>Dependency replies.yaml Status:</strong> $depRepStateEsc</div>
  <div class='tx-summary'><strong>Dependency replies.yaml File:</strong> $depRepFileEsc</div>
  <div class='tx-summary'><strong>Dependency Path In replies.yaml:</strong> $depTokenPathEsc</div>
  <div class='tx-summary'><strong>Dependency Parameter Value (replies.yaml):</strong> $depTokenValueEsc</div>
  $depRepBodyHtml
"@
      }

      @"
<section class='tx-section' id='$anchor'>
  <h3>$([System.Net.WebUtility]::HtmlEncode($tx))</h3>
  <div class='tx-summary'><strong>Summary:</strong> $summaryEsc</div>
  <div class='tx-summary'><strong>replies.yaml Status:</strong> $repliesStateEsc</div>
  <div class='tx-summary'><strong>replies.yaml File:</strong> $repliesFileEsc</div>
  <div class='tx-summary'><strong>Recommendation:</strong> $recommendationEsc</div>
  <div class='tx-summary'><strong>Transaction Window:</strong> $windowSummaryEsc</div>
  <h4>Matched Lines</h4>
  <ul>$matchedHtml</ul>
  <h4>Request JSON (Resolved Values)</h4>
  $requestJsonHtml
  <h4>Response JSON</h4>
  $responseJsonHtml
  <h4>replies.yaml Response Body</h4>
  $repliesBodyHtml
  $dependencySectionHtml
  <details>
    <summary><strong>Detailed Log Blocks</strong></summary>
    <ul>$rangeBlockHtml</ul>
  </details>
  <div><a href='#top'>Back to summary</a></div>
</section>
"@
    }) -join "`n"
  }

  $html = @"
<!DOCTYPE html>
<html lang='en'>
<head>
  <meta charset='UTF-8'>
  <title>$escapedScenario - Gatling Failure Report</title>
  <style>
    body { font-family: Segoe UI, Arial, sans-serif; margin: 24px; color: #1f2937; }
    h1 { margin-bottom: 4px; }
    .meta { margin-bottom: 16px; color: #4b5563; }
    table { border-collapse: collapse; width: 100%; }
    th, td { border: 1px solid #d1d5db; padding: 8px; vertical-align: top; font-size: 13px; }
    th { background: #f3f4f6; text-align: left; }
    pre { margin: 0; white-space: pre-wrap; word-wrap: break-word; font-family: Consolas, monospace; }
  </style>
</head>
<body id='top'>
  <h1>Gatling Failure Report</h1>
  <div class='meta'>
    <div><strong>Scenario:</strong> $escapedScenario</div>
    <div><strong>Host:</strong> $escapedHost</div>
    <div><strong>Generated:</strong> $generatedAt</div>
    <div><strong>Total Transactions:</strong> $totalTransactions</div>
    <div><strong>Total Failed Entries:</strong> $($summaryRows.Count)</div>
    <div><strong>Raw Log Copy:</strong> $escapedRawLogPath</div>
    <div><strong>replies.yaml Source:</strong> $escapedRepliesYamlPath</div>
  </div>
  <h2>Failed Transaction Counts by Type</h2>
  $failureTypeSummaryHtml
  <h2>Failed Transactions</h2>
  <table>
    <thead>
      <tr>
        <th>Transaction</th>
        <th>KO / Error</th>
        <th>replies.yaml</th>
        <th>Recommendation</th>
      </tr>
    </thead>
    <tbody>
      $summaryTableRows
    </tbody>
  </table>
  <h2>Details</h2>
  $detailSections
</body>
</html>
"@

  $htmlPath = Join-Path $scenarioReportDir ("$ScenarioName-$runTimestamp.html")
  $html | Set-Content -Path $htmlPath -Encoding UTF8

  Write-Host "Run complete. HTML report generated at: $htmlPath"
  Write-Host "Raw output copy saved at: $localRawCopyPath"
} finally {
  if (Test-Path $tempRoot) {
    Remove-Item -Path $tempRoot -Recurse -Force
  }
}



