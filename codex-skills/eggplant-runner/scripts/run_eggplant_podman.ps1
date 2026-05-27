param(
  [string]$HostName = "10.191.205.92",
  [string]$HostAlias = "",
  [string]$UserName = "root",
  [string]$KeyPath = "C:/Users/prakash/.ssh/id_gatling",
  [Parameter(Mandatory = $true)][string]$RemoteWorkspace,
  [string]$RepoName = "",
  [string]$SuiteRepoPath = "",
  [string]$AutomationHostPath = "",
  [Parameter(Mandatory = $true)][string]$EggplantSuiteName,
  [Parameter(Mandatory = $true)][string]$EggplantScriptName,
  [Parameter(Mandatory = $true)][string]$EggplantDomainUser,
  [ValidateSet("ABLA", "FHIR")][string]$SutDomain = "ABLA",
  [string]$LoginDataSourceFile = "",
  [string]$WorkflowDataSourceFile = "",
  [string]$EggplantIP = "",
  [string]$EggplantUsername,
  [string]$EggplantPassword,
  [string]$CitrixURL,
  [string]$CitrixURL2,
  [string]$CitrixStoreFrontUrl = "http://10.191.200.35/Citrix/AblCertDedCtx_storeWeb/default.htm#/mode/view-appshortcuts",
  [string]$CitrixStoreFrontUser = "",
  [string]$CitrixStoreFrontPassword = "",
  [switch]$PreferStoreFrontCitrixUrl,
  [string]$EggplantImage = "toolbox.dh2.cerner.com:5000/ablepf:latest",
  [string]$TimeZone = "America/Chicago",
  [int]$EndUsers = 1,
  [int]$Iterations = 0,
  [int]$DurationMinutes = 1,
  [switch]$NormalizeSuiteInfoIfScriptPresent,
  [switch]$EggplantDebug,
  [switch]$DiagnosticMode,
  [switch]$SkipResultCleanup,
  [switch]$SkipHelperPreflight,
  [switch]$SkipSetup,
  [switch]$DownloadArtifact,
  [string]$LocalArtifactDir = "C:/Users/prakash/Desktop/project/NBS/reports/eggplant"
)

$ErrorActionPreference = "Stop"
$SuppressedEggplantWarningPattern = "WARNING: The -compare: method for NSObject is deprecated."

$HostAliases = @{
  "fhirinj01" = "10.191.205.92"
}

$SutDomainDefaults = @{
  "ABLA" = @{
    SutHost            = "dh2vablasut02.dh2.cerner.com"
    CitrixKeyword      = "ABLA"
    CitrixStoreFrontUrl = "http://10.191.200.35/Citrix/AblCertDedCtx_storeWeb/default.htm#/mode/view-appshortcuts"
  }
  "FHIR" = @{
    SutHost            = "DH2VFHIRSUT01.DH2.cerner.com"
    CitrixKeyword      = "ABLFHIR"
    CitrixStoreFrontUrl = "http://10.191.200.35/Citrix/AblCertDedCtx_storeWeb/default.htm#/mode/view-appshortcuts"
  }
}

function Assert-CommandAvailable {
  param([string]$Name)
  if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
    throw "Required command not found in PATH: $Name"
  }
}

function Resolve-HostTarget {
  if (-not [string]::IsNullOrWhiteSpace($HostAlias)) {
    $aliasKey = $HostAlias.Trim().ToLowerInvariant()
    if (-not $HostAliases.ContainsKey($aliasKey)) {
      $supported = ($HostAliases.Keys | Sort-Object) -join ", "
      throw "Unknown HostAlias '$HostAlias'. Supported aliases: $supported"
    }
    $script:HostName = $HostAliases[$aliasKey]
    Write-Host "Resolved host alias '$HostAlias' to '$HostName'."
  }
}

function Invoke-External {
  param(
    [string]$Exe,
    [string[]]$CmdArgs
  )
  & $Exe @CmdArgs | Out-Host
  if ($LASTEXITCODE -ne 0) {
    throw "Command failed ($LASTEXITCODE): $Exe $($CmdArgs -join ' ')"
  }
}

function Invoke-Ssh {
  param([string]$RemoteCommand)
  $sshArgs = @(
    "-o", "StrictHostKeyChecking=no",
    "-o", "UserKnownHostsFile=/dev/null",
    "-i", $KeyPath,
    "$UserName@$HostName",
    $RemoteCommand
  )
  Invoke-External -Exe "ssh" -CmdArgs $sshArgs
}

function Invoke-SshIgnoreExit {
  param([string]$RemoteCommand)
  $sshArgs = @(
    "-o", "StrictHostKeyChecking=no",
    "-o", "UserKnownHostsFile=/dev/null",
    "-i", $KeyPath,
    "$UserName@$HostName",
    $RemoteCommand
  )
  & ssh @sshArgs | Out-Host
}

function Get-SshOutput {
  param([string]$RemoteCommand)
  $sshArgs = @(
    "-o", "StrictHostKeyChecking=no",
    "-o", "UserKnownHostsFile=/dev/null",
    "-i", $KeyPath,
    "$UserName@$HostName",
    $RemoteCommand
  )
  $output = & ssh @sshArgs
  if ($LASTEXITCODE -ne 0) {
    throw "Command failed ($LASTEXITCODE): ssh $($sshArgs -join ' ')"
  }
  return $output
}

function Invoke-ScpDownloadFile {
  param([string]$RemoteFile, [string]$LocalTargetPath)
  $scpArgs = @(
    "-o", "StrictHostKeyChecking=no",
    "-o", "UserKnownHostsFile=/dev/null",
    "-i", $KeyPath,
    "${UserName}@${HostName}:$RemoteFile",
    $LocalTargetPath
  )
  Invoke-External -Exe "scp" -CmdArgs $scpArgs
}

function Escape-ForSingleQuotes {
  param([string]$Text)
  return ($Text -replace "'", "'""'""'")
}

function Escape-ForSedReplacement {
  param([string]$Text)
  $escaped = $Text -replace "\\", "\\\\"
  $escaped = $escaped -replace "&", "\&"
  $escaped = $escaped -replace "@", "\@"
  return $escaped
}

function Invoke-SshBash {
  param([string]$BashScript)
  $escaped = Escape-ForSingleQuotes -Text $BashScript
  Invoke-Ssh "bash -lc '$escaped'"
}

function Get-CitrixBaseFromStoreFrontUrl {
  param([string]$StoreFrontUrl)
  if ([string]::IsNullOrWhiteSpace($StoreFrontUrl)) {
    return ""
  }
  try {
    $uri = [System.Uri]$StoreFrontUrl
    if ([string]::IsNullOrWhiteSpace($uri.Scheme) -or [string]::IsNullOrWhiteSpace($uri.Host)) {
      return ""
    }
    if ($uri.IsDefaultPort) {
      return ("{0}://{1}" -f $uri.Scheme, $uri.Host)
    }
    return ("{0}://{1}:{2}" -f $uri.Scheme, $uri.Host, $uri.Port)
  } catch {
    return ""
  }
}

function Normalize-CitrixCandidate {
  param(
    [string]$Candidate,
    [string]$CitrixBase
  )
  if ([string]::IsNullOrWhiteSpace($Candidate)) {
    return ""
  }

  $value = "$Candidate".Trim().Trim('"').Trim("'")
  $value = $value.TrimEnd(")", ",", ";")

  if ($value -match "^(?i)https?://") {
    return $value
  }

  if (-not [string]::IsNullOrWhiteSpace($CitrixBase)) {
    if ($value -match "^/Citrix/") {
      return "$CitrixBase$value"
    }
    if ($value -match "^Citrix/") {
      return "$CitrixBase/$value"
    }
  }

  return $value
}

function Resolve-CitrixShortcutFromSuite {
  param(
    [string]$RemoteSuitePath,
    [string]$PreferredKeyword = "",
    [string]$CitrixBase = ""
  )
  $remoteCmd = @"
test -d '$RemoteSuitePath' && grep -RhoE "https?://[^[:space:]\"]+|/Citrix/[^[:space:]\"]+|Citrix/[^[:space:]\"]+" '$RemoteSuitePath' 2>/dev/null | grep '#/launch/' | sort -u || true
"@
  $rawMatches = @(Get-SshOutput $remoteCmd | ForEach-Object { "$_".Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
  $matches = @($rawMatches | ForEach-Object { Normalize-CitrixCandidate -Candidate $_ -CitrixBase $CitrixBase } | Where-Object { $_ -match "(?i)#/launch/" } | Select-Object -Unique)
  if ($matches.Count -eq 0) {
    return ""
  }

  if (-not [string]::IsNullOrWhiteSpace($PreferredKeyword)) {
    $preferredMatch = $matches | Where-Object { $_ -match "(?i)$PreferredKeyword" } | Select-Object -First 1
    if (-not [string]::IsNullOrWhiteSpace($preferredMatch)) {
      return $preferredMatch
    }
    return ""
  }

  return ($matches | Select-Object -First 1)
}

function Assert-RemoteEggplantScriptExists {
  param(
    [string]$RemoteSuitePath,
    [string]$WorkflowName
  )
  $targetFile = "$RemoteSuitePath/Scripts/$WorkflowName.script"
  $checkCmd = "if [ -f '$targetFile' ]; then echo FOUND; else echo MISSING; fi"
  $exists = (Get-SshOutput $checkCmd | Select-Object -First 1)
  if ("$exists".Trim() -eq "FOUND") {
    Write-Host "Verified workflow script exists: $targetFile"
    return
  }

  $suggestCmd = "find '$RemoteSuitePath/Scripts' -maxdepth 2 -type f -name '*.script' 2>/dev/null | sed 's#.*/##' | grep -i '$WorkflowName' | head -n 10 || true"
  $suggestions = @(Get-SshOutput $suggestCmd)
  if ($suggestions.Count -eq 0) {
    $fallbackCmd = "find '$RemoteSuitePath/Scripts' -maxdepth 2 -type f -name '*.script' 2>/dev/null | sed 's#.*/##' | grep -i 'PathNet' | head -n 20 || true"
    $suggestions = @(Get-SshOutput $fallbackCmd)
  }

  if ($suggestions.Count -gt 0) {
    $joined = ($suggestions | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join ", "
    throw "Workflow script not found: $targetFile. Closest available scripts: $joined"
  }

  throw "Workflow script not found: $targetFile"
}

function Ensure-WorkflowResourceCsv {
  param(
    [string]$RemoteSuitePath,
    [string]$WorkflowName,
    [string]$SourceFileName,
    [string]$Suffix
  )
  $expectedFile = "$RemoteSuitePath/Resources/${WorkflowName}_${Suffix}.csv"
  $exists = (Get-SshOutput "if [ -f '$expectedFile' ]; then echo FOUND; else echo MISSING; fi" | Select-Object -First 1)
  if ("$exists".Trim() -eq "FOUND") {
    Write-Host "Verified ${Suffix} exists: $expectedFile"
    return
  }

  if (-not [string]::IsNullOrWhiteSpace($SourceFileName)) {
    $sourceFile = "$RemoteSuitePath/Resources/$SourceFileName"
    $copyCmd = "[ -f '$sourceFile' ] && cp -f '$sourceFile' '$expectedFile' && echo COPIED || echo SOURCE_MISSING"
    $copyResult = (Get-SshOutput $copyCmd | Select-Object -First 1)
    if ("$copyResult".Trim() -eq "COPIED") {
      Write-Host "Created expected ${Suffix} via copy:"
      Write-Host "  Source: $sourceFile"
      Write-Host "  Target: $expectedFile"
      return
    }
    throw "${Suffix} source file not found: $sourceFile"
  }

  $candidates = @(Get-SshOutput "find '$RemoteSuitePath/Resources' -maxdepth 1 -type f -name '*${Suffix}.csv' 2>/dev/null | sed 's#.*/##' | grep -i 'PathNet' | head -n 20 || true")
  $list = ($candidates | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join ", "
  if ([string]::IsNullOrWhiteSpace($list)) {
    throw "Required ${Suffix} missing: $expectedFile"
  }
  throw "Required ${Suffix} missing: $expectedFile. Provide a source-file mapping option to copy from an existing CSV. Available samples: $list"
}

Assert-CommandAvailable -Name "ssh"
Assert-CommandAvailable -Name "scp"
Resolve-HostTarget

$domainKey = $SutDomain.ToUpperInvariant()
if (-not $SutDomainDefaults.ContainsKey($domainKey)) {
  throw "Unsupported SutDomain '$SutDomain'. Supported values: ABLA, FHIR"
}
$domainDefaults = $SutDomainDefaults[$domainKey]
if (-not $PSBoundParameters.ContainsKey("EggplantIP") -or [string]::IsNullOrWhiteSpace($EggplantIP)) {
  $EggplantIP = $domainDefaults.SutHost
}
if (-not $PSBoundParameters.ContainsKey("CitrixStoreFrontUrl") -or [string]::IsNullOrWhiteSpace($CitrixStoreFrontUrl)) {
  $CitrixStoreFrontUrl = $domainDefaults.CitrixStoreFrontUrl
}
$citrixPreferredKeyword = $domainDefaults.CitrixKeyword
Write-Host "SUT domain profile: $domainKey"
Write-Host "Using sutHost default: $EggplantIP"

$repoPathNormalized = ($SuiteRepoPath -replace "\\", "/").TrimStart("/")
if ($repoPathNormalized.Length -gt 0 -and -not $repoPathNormalized.EndsWith("/")) {
  $repoPathNormalized = "$repoPathNormalized/"
}

$workspace = ($RemoteWorkspace -replace "\\", "/").TrimEnd("/")
if (-not [string]::IsNullOrWhiteSpace($AutomationHostPath)) {
  $automationHostPath = ($AutomationHostPath -replace "\\", "/").TrimEnd("/")
  if ($automationHostPath.ToLowerInvariant().EndsWith(".suite")) {
    $suitePath = $automationHostPath
    $dockerAutomationMountHostPath = ($automationHostPath -replace "/[^/]+\.suite$", "")
    if ([string]::IsNullOrWhiteSpace($dockerAutomationMountHostPath)) {
      $dockerAutomationMountHostPath = "/"
    }
  } else {
    $suitePath = "$automationHostPath/$EggplantSuiteName.suite"
    $dockerAutomationMountHostPath = $automationHostPath
  }
} else {
  if ([string]::IsNullOrWhiteSpace($RepoName)) {
    throw "RepoName is required when AutomationHostPath is not provided."
  }
  $repoRootPath = "$workspace/scripts/$RepoName"
  $automationHostPath = "$repoRootPath/$repoPathNormalized"
  $suitePath = "$automationHostPath$EggplantSuiteName.suite"
  $dockerAutomationMountHostPath = $automationHostPath
}
$eggplantSuitesPath = "$workspace/EggplantSuites"
$resultsPath = "$workspace/results"
$sutHostCsvPath = "$automationHostPath/sutHost.csv"
$sutCredentialsCsvPath = "$automationHostPath/sutCredentials.csv"
$envConfigDicPath = "$automationHostPath/EnvConfig.dic"

$debugArg = if ($EggplantDebug) { "--debug" } else { "" }

if ([string]::IsNullOrWhiteSpace($EggplantUsername) -and -not [string]::IsNullOrWhiteSpace($CitrixStoreFrontUser)) {
  $EggplantUsername = $CitrixStoreFrontUser
}
if ([string]::IsNullOrWhiteSpace($EggplantPassword) -and -not [string]::IsNullOrWhiteSpace($CitrixStoreFrontPassword)) {
  $EggplantPassword = $CitrixStoreFrontPassword
}

$citrixBase = Get-CitrixBaseFromStoreFrontUrl -StoreFrontUrl $CitrixStoreFrontUrl
$effectiveCitrixUrl = $CitrixURL
$citrixUrlSource = ""
if (-not [string]::IsNullOrWhiteSpace($effectiveCitrixUrl)) {
  $effectiveCitrixUrl = Normalize-CitrixCandidate -Candidate $effectiveCitrixUrl -CitrixBase $citrixBase
  $citrixUrlSource = "provided (normalized)"
}
if ([string]::IsNullOrWhiteSpace($effectiveCitrixUrl) -and -not $PreferStoreFrontCitrixUrl) {
  Write-Host "Attempting to auto-discover Citrix launch URL from suite files (preferred keyword: $citrixPreferredKeyword)..."
  $effectiveCitrixUrl = Resolve-CitrixShortcutFromSuite -RemoteSuitePath $suitePath -PreferredKeyword $citrixPreferredKeyword -CitrixBase $citrixBase
  if (-not [string]::IsNullOrWhiteSpace($effectiveCitrixUrl)) {
    $citrixUrlSource = "auto-discovered from suite ($citrixPreferredKeyword)"
  }
}
if ([string]::IsNullOrWhiteSpace($effectiveCitrixUrl) -and -not [string]::IsNullOrWhiteSpace($CitrixStoreFrontUrl)) {
  Write-Host "Using StoreFront URL as CitrixURL fallback."
  $effectiveCitrixUrl = $CitrixStoreFrontUrl
  $citrixUrlSource = "storefront fallback"
}
if (-not [string]::IsNullOrWhiteSpace($effectiveCitrixUrl)) {
  $CitrixURL = "$effectiveCitrixUrl".Trim().Trim('"').Trim("'")
  Write-Host "Identified CitrixURL ($citrixUrlSource): $CitrixURL"
  if ($CitrixURL -notmatch "(?i)#/launch/") {
    Write-Warning "CitrixURL does not include '#/launch/'. Provide -CitrixURL (full launch link) if this run requires direct app launch."
  }
}

Assert-RemoteEggplantScriptExists -RemoteSuitePath $suitePath -WorkflowName $EggplantScriptName
Ensure-WorkflowResourceCsv -RemoteSuitePath $suitePath -WorkflowName $EggplantScriptName -SourceFileName $LoginDataSourceFile -Suffix "LoginData"
Ensure-WorkflowResourceCsv -RemoteSuitePath $suitePath -WorkflowName $EggplantScriptName -SourceFileName $WorkflowDataSourceFile -Suffix "WorkflowData"

if (-not $SkipResultCleanup) {
  Write-Host "Cleaning previous Eggplant results before run..."
  $safeWorkflowName = $EggplantScriptName
  $cleanupCmd = @(
    "set -e",
    "mkdir -p '$resultsPath'",
    "if [ '$resultsPath' != '/' ] && [ -n '$resultsPath' ]; then find '$resultsPath' -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null || true; fi",
    "rm -f '$workspace/eggplant_log.zip' 2>/dev/null || true",
    "find '$workspace' -maxdepth 1 -type f -name 'eggplant_docker_${safeWorkflowName}_*.log' -delete 2>/dev/null || true"
  ) -join "; "
  Invoke-Ssh "bash -lc '$cleanupCmd'"
} else {
  Write-Host "Skipping prior-result cleanup due to -SkipResultCleanup."
}

if (-not $SkipSetup) {
  Write-Host "Running setup steps (Jenkins-inspired 'Setup Eggplant')..."
  Invoke-SshBash @"
set -e
mkdir -p '$workspace/scripts' '$eggplantSuitesPath' '$resultsPath'
chmod 777 '$resultsPath' || true
chmod -R 777 '$automationHostPath' || true
chmod -R 777 '$suitePath' || true
"@

  if (-not [string]::IsNullOrWhiteSpace($EggplantIP)) {
    Invoke-SshBash @"
set -e
mkdir -p '$automationHostPath'
cat > '$sutHostCsvPath' <<'EOF'
sutHost
$EggplantIP
EOF
"@
  }

  if (-not [string]::IsNullOrWhiteSpace($EggplantUsername) -and -not [string]::IsNullOrWhiteSpace($EggplantPassword)) {
    Invoke-SshBash @"
set -e
mkdir -p '$automationHostPath'
cat > '$sutCredentialsCsvPath' <<'EOF'
sutUsername,sutPassword
$EggplantUsername,$EggplantPassword
EOF
"@
  }

  if (-not [string]::IsNullOrWhiteSpace($CitrixURL)) {
    Invoke-SshBash @"
set -e
mkdir -p '$automationHostPath'
cat > '$envConfigDicPath' <<'EOF'
CitrixURL=$CitrixURL
EOF
"@

    $sedCitrix1 = Escape-ForSedReplacement -Text $CitrixURL
    $sedCitrix2 = if ([string]::IsNullOrWhiteSpace($CitrixURL2)) { "" } else { Escape-ForSedReplacement -Text $CitrixURL2 }
    $dataLoaderPattern = "${EggplantScriptName}_DataLoader.script"

    $citrixUpdateScript = @(
"set -e",
"if [ -d '$suitePath/Scripts/DataLoader' ]; then",
"  dataLoaderFile=`$(find '$suitePath/Scripts/DataLoader' -iname '$dataLoaderPattern' -print -quit || true)",
"  if [ -n `"`$dataLoaderFile`" ]; then",
"    sed -e 's@^.*set citrixShortcut .*@        set citrixShortcut to `"$sedCitrix1`"@ig' -i `"`$dataLoaderFile`""
)
    if (-not [string]::IsNullOrWhiteSpace($CitrixURL2)) {
      $citrixUpdateScript += "    sed -e 's@^.*set citrixShortcut2 .*@        set citrixShortcut2 to `"$sedCitrix2`"@ig' -i `"`$dataLoaderFile`""
    }
    $citrixUpdateScript += @(
"  fi",
"fi"
    )
    Invoke-SshBash ($citrixUpdateScript -join "`n")
  }

  # Normalize legacy/Windows helper-suite paths for Linux container runtime.
  Invoke-SshBash @"
set -e
normalize_dir() {
  local target_dir="`$1"
  [ -d "`$target_dir" ] || return 0
  find "`$target_dir" -type f \( -name 'SuiteInfo' -o -name '*.script' \) -print0 | \
    while IFS= read -r -d '' f; do
      if command -v perl >/dev/null 2>&1; then
        perl -0777 -i -pe '
          s{(?:/)?C:/(?:EggplantSuites|EggPlantSuites|Eggplantsuites)/([^"'"'"'\n]*?\.suite)}{/home/eggplant/EggplantSuites/$1}ig;
          s{C:\\\\(?:EggplantSuites|EggPlantSuites|Eggplantsuites)\\\\([^"'"'"'\n]*?\.suite)}{/home/eggplant/EggplantSuites/$1}ig;
          s{(?:/)?N:/Wayne_Wertz/VA-Repos/([^"'"'"'\n]*?\.suite)}{/home/eggplant/EggplantSuites/$1}ig;
          s{<Suite_[Rr]oot>/\.\./([^"'"'"'\n]*?\.suite)}{/home/eggplant/EggplantSuites/$1}g;
          s{\./([^"'"'"'\n]*?\.suite)}{/home/eggplant/EggplantSuites/$1}g;
          s{VA_HAndlers}{VA_Handlers}g;
          s{IPDev--Shared-Windows}{IPDev-Shared-Windows}g;
          s{Millenium}{Millennium}g;
        ' "`$f" || true
      else
        sed -i \
          -e 's#/C:/EggplantSuites#/home/eggplant/EggplantSuites#g' \
          -e 's#C:/EggplantSuites#/home/eggplant/EggplantSuites#g' \
          -e 's#C:/EggPlantSuites#/home/eggplant/EggplantSuites#g' \
          -e 's#C:/Eggplantsuites#/home/eggplant/EggplantSuites#g' \
          -e 's#/N:/Wayne_Wertz/VA-Repos/#/home/eggplant/EggplantSuites/#g' \
          -e 's#N:/Wayne_Wertz/VA-Repos/#/home/eggplant/EggplantSuites/#g' \
          -e 's#<Suite_root>/\\.\\./#/home/eggplant/EggplantSuites/#g' \
          -e 's#<Suite_Root>/\\.\\./#/home/eggplant/EggplantSuites/#g' \
          -e 's#VA_HAndlers#VA_Handlers#g' \
          -e 's#IPDev--Shared-Windows#IPDev-Shared-Windows#g' \
          -e 's#Millenium#Millennium#g' \
          "`$f" || true
      fi
    done
}

normalize_dir '$suitePath'
normalize_dir '$eggplantSuitesPath'
"@

  # Ensure helper suites have a SuiteInfo file; some repos ship only Scripts/ and rely on generation.
  Invoke-SshBash @"
set -e
created_count=0
if [ -d '$eggplantSuitesPath' ]; then
  while IFS= read -r -d '' suite_dir; do
    suite_info="`$suite_dir/SuiteInfo"
    if [ ! -f "`$suite_info" ]; then
      : > "`$suite_info"
      chmod 666 "`$suite_info" || true
      created_count=`$((created_count + 1))
    fi
  done < <(find '$eggplantSuitesPath' -type d -name '*.suite' -print0 2>/dev/null)
fi
echo "Auto-created missing helper SuiteInfo files: `$created_count"
"@

  if ($NormalizeSuiteInfoIfScriptPresent) {
    $updateScriptPath = "$automationHostPath/update_suiteinfo.py"
    $suiteInfoCmd = "[ -f '$updateScriptPath' ] && echo 'Normalizing SuiteInfo files using update_suiteinfo.py...' && docker run --rm -v '${automationHostPath}:/workingdir' python:3.9 bash -lc ""find /workingdir -name SuiteInfo -exec /workingdir/update_suiteinfo.py -f {} \\\\;"" && docker run --rm -v '${eggplantSuitesPath}:/EggplantSuites' -v '${automationHostPath}:/eggplant_docker' python:3.9 bash -lc ""find /EggplantSuites -name SuiteInfo -exec /eggplant_docker/update_suiteinfo.py -f {} \\\\;"" || echo 'update_suiteinfo.py not found in automation path; skipping SuiteInfo normalization.'"
    Invoke-Ssh $suiteInfoCmd
  }
} else {
  Write-Host "Skipping setup steps due to -SkipSetup."
  Write-Host "Ensuring required runtime directories exist..."
  Invoke-Ssh "mkdir -p '$workspace/scripts' '$eggplantSuitesPath' '$resultsPath'"
}

if (-not $SkipHelperPreflight) {
Write-Host "Running helper-suite preflight checks..."
Invoke-SshBash @"
set -e
tmp_refs="`$(mktemp)"
tmp_missing="`$(mktemp)"
helper_host_root='$eggplantSuitesPath'

collect_refs_from_dir() {
  local target_dir="`$1"
  [ -d "`$target_dir" ] || return 0
  find "`$target_dir" -type f \( -name 'SuiteInfo' -o -name '*.script' \) -print0 2>/dev/null | \
    while IFS= read -r -d '' f; do
      grep -Eho '/home/eggplant/EggplantSuites/[^"'"'"'[:space:]]+\.suite|/C:/EggplantSuites/[^"'"'"'[:space:]]+\.suite|C:/EggplantSuites/[^"'"'"'[:space:]]+\.suite|C:/EggPlantSuites/[^"'"'"'[:space:]]+\.suite|C:/Eggplantsuites/[^"'"'"'[:space:]]+\.suite|N:/Wayne_Wertz/VA-Repos/[^"'"'"'[:space:]]+\.suite|/N:/Wayne_Wertz/VA-Repos/[^"'"'"'[:space:]]+\.suite|<Suite_[Rr]oot>/\.\./[^"'"'"'[:space:]]+\.suite|\./[^"'"'"'[:space:]]+\.suite' "`$f" 2>/dev/null || true
    done
}

normalize_ref() {
  local ref="`$1"
  case "`$ref" in
    /home/eggplant/EggplantSuites/*)
      printf '%s/%s\n' "`$helper_host_root" "`${ref#/home/eggplant/EggplantSuites/}"
      ;;
    /C:/EggplantSuites/*)
      printf '%s/%s\n' "`$helper_host_root" "`${ref#/C:/EggplantSuites/}"
      ;;
    C:/EggplantSuites/*)
      printf '%s/%s\n' "`$helper_host_root" "`${ref#C:/EggplantSuites/}"
      ;;
    C:/EggPlantSuites/*)
      printf '%s/%s\n' "`$helper_host_root" "`${ref#C:/EggPlantSuites/}"
      ;;
    C:/Eggplantsuites/*)
      printf '%s/%s\n' "`$helper_host_root" "`${ref#C:/Eggplantsuites/}"
      ;;
    /N:/Wayne_Wertz/VA-Repos/*)
      printf '%s/%s\n' "`$helper_host_root" "`${ref#/N:/Wayne_Wertz/VA-Repos/}"
      ;;
    N:/Wayne_Wertz/VA-Repos/*)
      printf '%s/%s\n' "`$helper_host_root" "`${ref#N:/Wayne_Wertz/VA-Repos/}"
      ;;
    "<Suite_root>/../"*)
      printf '%s/%s\n' "`$helper_host_root" "`${ref#<Suite_root>/../}"
      ;;
    "<Suite_Root>/../"*)
      printf '%s/%s\n' "`$helper_host_root" "`${ref#<Suite_Root>/../}"
      ;;
    ./*)
      printf '%s/%s\n' "`$helper_host_root" "`${ref#./}"
      ;;
    *)
      printf '%s\n' "`$ref"
      ;;
  esac
}

{
  collect_refs_from_dir '$suitePath'
  collect_refs_from_dir '$eggplantSuitesPath'
} | while IFS= read -r ref; do
  [ -z "`$ref" ] && continue
  normalize_ref "`$ref"
done | sort -u > "`$tmp_refs"

if [ ! -s "`$tmp_refs" ]; then
  echo "Helper preflight: no helper-suite references found to validate."
  rm -f "`$tmp_refs" "`$tmp_missing"
  exit 0
fi

while IFS= read -r helper_path; do
  [ -z "`$helper_path" ] && continue
  if [ ! -d "`$helper_path" ]; then
    printf '%s\n' "`$helper_path" >> "`$tmp_missing"
  fi
done < "`$tmp_refs"

if [ -s "`$tmp_missing" ]; then
  echo "Helper preflight FAILED. Missing helper suites:"
  cat "`$tmp_missing"
  rm -f "`$tmp_refs" "`$tmp_missing"
  exit 86
fi

echo "Helper preflight passed: all referenced helper suites exist."
rm -f "`$tmp_refs" "`$tmp_missing"
"@
} else {
  Write-Host "Skipping helper-suite preflight due to -SkipHelperPreflight."
}

Write-Host "Checking Docker availability..."
Invoke-Ssh "docker --version"

Write-Host "Running Eggplant using Docker..."
$dockerRunCmd = @(
  "docker run --rm",
  "-w /home/eggplant",
  "-e EGGPLANT_ACCEPT_EULA=true",
  "-e EGGPLANT_ACCEPT_PRIVACY_AGREEMENT=true",
  "-e TZ='$TimeZone'",
  "-v '${dockerAutomationMountHostPath}:/home/eggplant/automation'",
  "-v '${eggplantSuitesPath}:/home/eggplant/EggplantSuites'",
  "-v '${resultsPath}:/home/eggplant/results'",
  "'$EggplantImage'",
  "--suite_name '$EggplantSuiteName'",
  "--workflow_name '$EggplantScriptName'",
  "--end_users $EndUsers",
  $(if ($Iterations -gt 0) { "--iterations $Iterations" } else { "--duration $DurationMinutes" }),
  "$debugArg"
) -join " "

$remoteRunCmd = @(
  "set -e",
  "cd '$workspace'",
  "chown -R 1000:1000 scripts/ EggplantSuites/ || true",
  $dockerRunCmd
) -join " "

$diagnosticLogPath = ""
$runExitCode = 0
try {
  if ($DiagnosticMode) {
    $stamp = Get-Date -Format "yyyyMMddHHmmss"
    $safeWorkflow = ($EggplantScriptName -replace "[^A-Za-z0-9._-]", "_")
    $diagnosticLogPath = "$workspace/eggplant_docker_${safeWorkflow}_$stamp.log"
    Write-Host "Diagnostic mode enabled. Remote Docker log: $diagnosticLogPath"

    $diagnosticCmd = @(
      "set -o pipefail",
      "cd '$workspace'",
      "chown -R 1000:1000 scripts/ EggplantSuites/ || true",
      "$dockerRunCmd 2>&1 | tee '$diagnosticLogPath'",
      "exit `${PIPESTATUS[0]}"
    ) -join "; "
    Invoke-Ssh "bash -lc '$diagnosticCmd'"
  } else {
    Invoke-Ssh $remoteRunCmd
  }
} catch {
  $runExitCode = $LASTEXITCODE
  if ($DiagnosticMode -and -not [string]::IsNullOrWhiteSpace($diagnosticLogPath)) {
    Write-Warning "Docker run returned non-zero status. Diagnostic log retained at: $diagnosticLogPath"
  }
  Write-Warning "Docker run returned non-zero status. Continuing to evaluate Eggplant log status like Jenkins stage."
}

if ($DiagnosticMode -and -not [string]::IsNullOrWhiteSpace($diagnosticLogPath)) {
  Write-Host "Diagnostic log tail (last 80 lines):"
  try {
    $diagTail = Get-SshOutput "if [ -f '$diagnosticLogPath' ]; then tail -n 200 '$diagnosticLogPath' | grep -F -v '$SuppressedEggplantWarningPattern' | tail -n 80; else echo 'DIAGNOSTIC_LOG_NOT_FOUND'; fi"
    $diagTail | ForEach-Object { Write-Host $_ }
  } catch {
    Write-Warning "Unable to read diagnostic log tail from remote host."
  }
}

$domainSplit = $EggplantDomainUser -split "\\", 2
$usernameInLog = if ($domainSplit.Count -eq 2) { $domainSplit[1].ToLowerInvariant() } else { $EggplantDomainUser.ToLowerInvariant() }
$logFile = "$resultsPath/${EggplantScriptName}_vu1_${usernameInLog}/runscript_${EggplantScriptName}_vu1_${usernameInLog}.log"

Write-Host "Expected Eggplant log: $logFile"

$backupStamp = Get-Date -Format "yyyyMMddHHmmss"
$logBackupFile = "${logFile}.pre_filter_${backupStamp}.bak"
$sanitizeLogCmd = @(
  "if [ -f '$logFile' ]; then",
  "  cp -f '$logFile' '$logBackupFile';",
  "  grep -F -v '$SuppressedEggplantWarningPattern' '$logBackupFile' > '${logFile}.tmp' || true;",
  "  mv -f '${logFile}.tmp' '$logFile';",
  "  echo '$logBackupFile';",
  "else",
  "  echo '';",
  "fi"
) -join " "
$logBackupPathOut = (Get-SshOutput $sanitizeLogCmd | Select-Object -First 1)
if (-not [string]::IsNullOrWhiteSpace("$logBackupPathOut")) {
  Write-Host "Backed up runscript log before warning-line cleanup: $logBackupPathOut"
}

$tailOutput = Get-SshOutput "if [ -f '$logFile' ]; then grep -F -v '$SuppressedEggplantWarningPattern' '$logFile' | tail -n 1 || true; else echo 'LOG_NOT_FOUND'; fi"
Write-Host "Last log line:"
$tailOutput | ForEach-Object { Write-Host $_ }

$statusLine = Get-SshOutput "if [ -f '$logFile' ]; then grep $'\t' '$logFile' | tail -n 1 | cut -f2 || true; else echo 'FAILED'; fi" | Select-Object -First 1
$eggplantStatus = if ($null -eq $statusLine) { "" } else { "$statusLine".Trim() }
if ([string]::IsNullOrWhiteSpace($eggplantStatus)) {
  $eggplantStatus = "FAILED"
}

if ($eggplantStatus -eq "SUCCESS") {
  Write-Host "Eggplant execution status: SUCCESS"
} else {
  Write-Host "Eggplant execution status: FAILED"
}

$zipPath = "$workspace/eggplant_log.zip"
Write-Host "Creating remote artifact: $zipPath"
Invoke-Ssh "cd '$workspace' && rm -f eggplant_log.zip && zip -r eggplant_log.zip results"

if ($DownloadArtifact) {
  New-Item -ItemType Directory -Force -Path $LocalArtifactDir | Out-Null
  $timestamp = Get-Date -Format "yyyyMMddHHmmss"
  $localZip = Join-Path $LocalArtifactDir ("eggplant_log_" + $EggplantScriptName + "_" + $timestamp + ".zip")
  Write-Host "Downloading artifact to: $localZip"
  Invoke-ScpDownloadFile -RemoteFile $zipPath -LocalTargetPath $localZip
}

if ($eggplantStatus -ne "SUCCESS") {
  throw "Eggplant execution failed based on log status: $eggplantStatus"
}

Write-Host "Completed."
