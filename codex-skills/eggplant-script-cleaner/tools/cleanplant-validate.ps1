param(
  [Parameter(Mandatory = $true)]
  [string]$Workflow,
  [string]$SuiteRoot = ".",
  [ValidateSet("On","Off")]
  [string]$ConversionMode = "On",
  [ValidateSet("Verbose","Standard")]
  [string]$FailureMode = "Verbose"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-LineCommentStart {
  param([string]$Line, [int]$StartIndex)

  $cursor = $StartIndex
  while ($cursor -lt $Line.Length) {
    $hit = $Line.IndexOf("//", $cursor)
    if ($hit -lt 0) { return -1 }

    $prefix = $Line.Substring(0, $hit)
    if ($prefix.Trim().Length -eq 0) { return $hit }
    if ($hit -gt 0 -and [char]::IsWhiteSpace($Line[$hit - 1])) { return $hit }

    $cursor = $hit + 2
  }

  return -1
}

function Get-ActiveLineRecords {
  param([string]$Path)

  $lines = @(Get-Content -LiteralPath $Path)
  $records = @()
  $inBlockComment = $false

  for ($i = 0; $i -lt $lines.Count; $i++) {
    $line = [string]$lines[$i]
    $active = ""
    $cursor = 0

    while ($cursor -lt $line.Length) {
      if ($inBlockComment) {
        $end = $line.IndexOf("*)", $cursor)
        if ($end -lt 0) {
          $cursor = $line.Length
          break
        }
        $cursor = $end + 2
        $inBlockComment = $false
        continue
      }

      $blockStart = $line.IndexOf("(*", $cursor)
      $slashStart = Get-LineCommentStart -Line $line -StartIndex $cursor
      $dashStart = -1
      if ($line.Substring($cursor).TrimStart().StartsWith("--")) {
        $dashStart = $cursor + ($line.Substring($cursor).Length - $line.Substring($cursor).TrimStart().Length)
      }

      $commentStarts = @(@($blockStart, $slashStart, $dashStart) | Where-Object { $_ -ge 0 } | Sort-Object)
      if ($commentStarts.Count -eq 0) {
        $active += $line.Substring($cursor)
        $cursor = $line.Length
        break
      }

      $nextComment = [int]$commentStarts[0]
      if ($nextComment -gt $cursor) {
        $active += $line.Substring($cursor, $nextComment - $cursor)
      }

      if ($nextComment -eq $blockStart) {
        $end = $line.IndexOf("*)", $nextComment + 2)
        if ($end -lt 0) {
          $inBlockComment = $true
          $cursor = $line.Length
        } else {
          $cursor = $end + 2
        }
        continue
      }

      $cursor = $line.Length
    }

    $records += [pscustomobject]@{
      LineNumber = $i + 1
      Original = $line
      Active = $active
    }
  }

  return @($records)
}

function Test-RipgrepExecutable {
  param([string]$Path)

  if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) {
    return $false
  }

  try {
    $null = & $Path --version 2>$null
    return ($LASTEXITCODE -eq 0)
  } catch {
    return $false
  }
}

function Resolve-OpenAiRipgrepPath {
  $candidates = New-Object System.Collections.Generic.List[string]

  $windowsApps = Join-Path $env:ProgramFiles "WindowsApps"
  if (Test-Path -LiteralPath $windowsApps) {
    Get-ChildItem -LiteralPath $windowsApps -Directory -Filter "OpenAI.Codex_*" -ErrorAction SilentlyContinue |
      Sort-Object Name -Descending |
      ForEach-Object {
        $candidates.Add((Join-Path $_.FullName "app\resources\rg.exe"))
      }
  }

  $extensionRoot = Join-Path $env:USERPROFILE ".vscode\extensions"
  if (Test-Path -LiteralPath $extensionRoot) {
    Get-ChildItem -LiteralPath $extensionRoot -Directory -Filter "openai.chatgpt-*-win32-x64" -ErrorAction SilentlyContinue |
      Sort-Object Name -Descending |
      ForEach-Object {
        $candidates.Add((Join-Path $_.FullName "bin\windows-x86_64\rg.exe"))
      }
  }

  foreach ($candidate in $candidates) {
    if (Test-RipgrepExecutable -Path $candidate) {
      return $candidate
    }
  }

  return $null
}

$script:RipgrepPath = Resolve-OpenAiRipgrepPath

function Invoke-OpenAiRipgrep {
  param(
    [string]$Pattern,
    [string]$Path,
    [switch]$IgnoreCase
  )

  if ([string]::IsNullOrWhiteSpace($script:RipgrepPath)) {
    throw "No runnable OpenAI/Codex rg.exe was found."
  }

  $args = @("--line-number", "--no-heading", "--color", "never")
  if ($IgnoreCase) { $args += "-i" }
  $args += @("--", $Pattern, $Path)

  try {
    $hits = & $script:RipgrepPath @args 2>$null
    $exitCode = $LASTEXITCODE
  } catch {
    throw ("OpenAI/Codex rg.exe failed to run: {0}" -f $_.Exception.Message)
  }

  if ($exitCode -eq 1) { return @() }
  if ($exitCode -ne 0) {
    throw ("OpenAI/Codex rg.exe failed for pattern '{0}' in '{1}' with exit code {2}." -f $Pattern, $Path, $exitCode)
  }

  return @($hits)
}

function Get-Count {
  param(
    [string]$Pattern,
    [string]$Path,
    [switch]$IncludeComments,
    [switch]$IgnoreCase
  )

  return (@(Get-RgHits -Pattern $Pattern -Path $Path -IncludeComments:$IncludeComments -IgnoreCase:$IgnoreCase).Count)
}

function Get-RgHits {
  param(
    [string]$Pattern,
    [string]$Path,
    [switch]$IncludeComments,
    [switch]$IgnoreCase
  )

  $options = [System.Text.RegularExpressions.RegexOptions]::None
  if ($IgnoreCase) { $options = $options -bor [System.Text.RegularExpressions.RegexOptions]::IgnoreCase }
  $rawHits = @(Invoke-OpenAiRipgrep -Pattern $Pattern -Path $Path -IgnoreCase:$IgnoreCase)
  if ($IncludeComments) {
    return @($rawHits)
  }

  $recordsByLine = @{}
  foreach ($record in (Get-ActiveLineRecords -Path $Path)) {
    $recordsByLine[[int]$record.LineNumber] = $record
  }

  $hits = @()
  foreach ($rawHit in $rawHits) {
    if ($rawHit -notmatch '^(?<line>\d+):') { continue }
    $lineNumber = [int]$Matches["line"]
    if (-not $recordsByLine.ContainsKey($lineNumber)) { continue }
    $active = [string]$recordsByLine[$lineNumber].Active
    if ([regex]::IsMatch($active, $Pattern, $options)) {
      $hits += ("{0}:{1}" -f $lineNumber, $active.TrimEnd())
    }
  }
  return @($hits)
}

function Split-CsvFields {
  param([string]$Line)

  $fields = New-Object System.Collections.Generic.List[string]
  $field = New-Object System.Text.StringBuilder
  $inQuotes = $false

  for ($i = 0; $i -lt $Line.Length; $i++) {
    $char = $Line[$i]
    if ($char -eq '"') {
      if ($inQuotes -and ($i + 1) -lt $Line.Length -and $Line[$i + 1] -eq '"') {
        [void]$field.Append('"')
        $i++
        continue
      }
      $inQuotes = -not $inQuotes
      continue
    }
    if ($char -eq ',' -and -not $inQuotes) {
      $fields.Add($field.ToString())
      $field.Clear() | Out-Null
      continue
    }
    [void]$field.Append($char)
  }

  $fields.Add($field.ToString())
  return @($fields)
}

function Join-CsvFields {
  param([string[]]$Fields)

  if ($null -eq $Fields) { return "" }

  $encoded = New-Object System.Collections.Generic.List[string]
  foreach ($field in $Fields) {
    $value = if ($null -eq $field) { "" } else { [string]$field }
    $escaped = $value.Replace('"', '""')
    $needsQuotes = $value.Contains(",") -or $value.Contains('"') -or $value.Contains("`r") -or $value.Contains("`n")
    if ($needsQuotes) {
      $encoded.Add(('"{0}"' -f $escaped))
    } else {
      $encoded.Add($escaped)
    }
  }

  return ($encoded -join ",")
}

function Get-CsvInfo {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) {
    return [pscustomobject]@{
      Exists = $false
      Headers = @()
      HeaderCount = 0
      DataCount = 0
      TotalLines = 0
      ColumnMismatch = $false
    }
  }

  $lines = @(Get-Content -LiteralPath $Path)
  $headers = @()
  if ($lines.Count -gt 0) {
    $headers = @(Split-CsvFields -Line $lines[0])
  }
  $headerCount = $headers.Count
  $dataCount = [Math]::Max(0, $lines.Count - 1)
  $columnMismatch = $false

  if ($headerCount -gt 0 -and $dataCount -gt 0) {
    for ($i = 1; $i -lt $lines.Count; $i++) {
      $valueCount = @(Split-CsvFields -Line $lines[$i]).Count
      if ($valueCount -ne $headerCount) {
        $columnMismatch = $true
        break
      }
    }
  }

  return [pscustomobject]@{
    Exists = $true
    Headers = $headers
    HeaderCount = $headerCount
    DataCount = $dataCount
    TotalLines = $lines.Count
    ColumnMismatch = $columnMismatch
  }
}

function Test-WfTestCaseBodyIndentation {
  param([string]$Path)

  $lines = Get-Content -LiteralPath $Path
  $issues = @()
  $inCase = $false
  $caseIndent = ""
  $indentDepth = 1
  $caseStartLine = 0

  for ($i = 0; $i -lt $lines.Count; $i++) {
    $line = $lines[$i]
    $lineNumber = $i + 1


    if (-not $inCase) {
      if ($line -match '^(?<indent>[ \t]*)Run "CTX/AbilitiesCitrixMethods"\.wfTestCase\b') {
        $inCase = $true
        $caseIndent = $Matches.indent
        $indentDepth = 1
        $caseStartLine = $lineNumber
      }
      continue
    }

    if ($line -match '^[ \t]*EndTestCase wfStep\b') {
      $inCase = $false
      $caseIndent = ""
      $indentDepth = 1
      $caseStartLine = 0
      continue
    }

    if ($line.Trim().Length -eq 0) {
      continue
    }

    $trimmed = $line.TrimStart()
    $actualIndent = ([regex]::Match($line, '^[ \t]*')).Value

    $isElse = $trimmed -match '^(?i)else(\b|$)'
    $isEndIf = $trimmed -match '^(?i)end if\b'
    $isEndRepeat = $trimmed -match '^(?i)end repeat\b'
    $isIf = $trimmed -match '^(?i)if\b'
    $isInlineIf = $isIf -and ($trimmed -match '^(?i)if\b.*\bthen\b.+\S')
    $isBlockIf = $isIf -and -not $isInlineIf
    $isRepeat = $trimmed -match '^(?i)repeat\b'

    $expectedDepth = $indentDepth
    if ($isElse -or $isEndIf -or $isEndRepeat) {
      $expectedDepth = [Math]::Max(1, $indentDepth - 1)
    }

    $expectedIndent = $caseIndent + ("`t" * $expectedDepth)
    if ($actualIndent -ne $expectedIndent) {
      $issues += [pscustomobject]@{
        Line = $lineNumber
        Message = "Line inside wfTestCase has inconsistent nested indentation."
        Content = $line.TrimEnd()
      }
    }

    if ($isElse) {
      # else closes prior branch and opens a new one at the same nesting level
      continue
    }
    if ($isEndIf -or $isEndRepeat) {
      $indentDepth = [Math]::Max(1, $indentDepth - 1)
      continue
    }
    if ($isBlockIf -or $isRepeat) {
      $indentDepth++
    }
  }

  if ($inCase) {
    $issues += [pscustomobject]@{
      Line = $caseStartLine
      Message = "wfTestCase block is missing EndTestCase wfStep."
      Content = $lines[$caseStartLine - 1].TrimEnd()
    }
  }

  return $issues
}

function Test-IfElseIndentationInWfTestCase {
  param([string]$Path)

  $lines = Get-Content -LiteralPath $Path
  $issues = @()
  $inCase = $false
  $ifIndentStack = New-Object System.Collections.ArrayList

  for ($i = 0; $i -lt $lines.Count; $i++) {
    $line = $lines[$i]
    $lineNumber = $i + 1

    if (-not $inCase) {
      if ($line -match '^[ \t]*Run "CTX/AbilitiesCitrixMethods"\.wfTestCase\b') {
        $inCase = $true
        $ifIndentStack.Clear() | Out-Null
      }
      continue
    }

    if ($line -match '^[ \t]*EndTestCase wfStep\b') {
      if ($ifIndentStack.Count -gt 0) {
        foreach ($entry in $ifIndentStack) {
          $issues += [pscustomobject]@{
            Line = $entry.Line
            Message = "if block is missing matching End If before EndTestCase."
            Content = $lines[$entry.Line - 1].TrimEnd()
          }
        }
      }
      $inCase = $false
      $ifIndentStack.Clear() | Out-Null
      continue
    }

    if ($line.Trim().Length -eq 0) {
      continue
    }

    $trimmed = $line.TrimStart()
    $actualIndent = ([regex]::Match($line, '^[ \t]*')).Value

    $isElseIf = $trimmed -match '^(?i)else if\b'
    $isElseOnly = $trimmed -match '^(?i)else(\b|$)' -and -not $isElseIf
    $isEndIf = $trimmed -match '^(?i)end if\b'
    $isIf = $trimmed -match '^(?i)if\b'
    $isInlineIf = $trimmed -match '^(?i)if\b.*\bthen\b.+\S'
    $isBlockIf = $isIf -and -not $isInlineIf

    if ($isElseIf -or $isElseOnly -or $isEndIf) {
      if ($ifIndentStack.Count -eq 0) {
        $issues += [pscustomobject]@{
          Line = $lineNumber
          Message = "Else/End If appears without a matching If."
          Content = $line.TrimEnd()
        }
        continue
      }

      $expectedIndent = $ifIndentStack[$ifIndentStack.Count - 1].Indent
      if ($actualIndent -ne $expectedIndent) {
        $issues += [pscustomobject]@{
          Line = $lineNumber
          Message = "Else/End If indentation does not align with matching If."
          Content = $line.TrimEnd()
        }
      }

      if ($isEndIf) {
        $ifIndentStack.RemoveAt($ifIndentStack.Count - 1)
      }
      continue
    }

    if ($isBlockIf) {
      [void]$ifIndentStack.Add([pscustomobject]@{
        Line = $lineNumber
        Indent = $actualIndent
      })
    }
  }

  return $issues
}

function Test-MalformedSeparatorComments {
  param([string]$Path)

  $lines = Get-Content -LiteralPath $Path
  $issues = @()

  for ($i = 0; $i -lt $lines.Count; $i++) {
    $line = $lines[$i]
    $lineNumber = $i + 1

    if ($line -match '^[ \t]*\((=+)\*\)[ \t]*$' -or
        $line -match '^[ \t]*\(\*(=+)\)[ \t]*$' -or
        $line -match '^[ \t]*\((=+)\)[ \t]*$') {
      $issues += [pscustomobject]@{
        Line = $lineNumber
        Message = "Malformed separator comment delimiter."
        Content = $line.TrimEnd()
      }
    }
  }

  return $issues
}

function Test-IsFormattingLine {
  param([string]$Line)

  $trimmed = $Line.Trim()
  if ($trimmed.Length -eq 0) { return $true }
  if ($trimmed.StartsWith("//") -or $trimmed.StartsWith("--")) { return $true }
  if ($trimmed -match '^\(\*[-=*#_ ]*\*\)$') { return $true }
  if ($trimmed -match '^[-=*#_]{3,}$') { return $true }
  return $false
}

function Normalize-AppToken {
  param([string]$Value)
  if ([string]::IsNullOrWhiteSpace($Value)) { return "" }
  $token = $Value.Trim()
  $token = [regex]::Replace($token, '\.exe$', '', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
  $token = [regex]::Replace($token, '[^A-Za-z0-9]', '')
  return $token.ToLowerInvariant()
}

function Get-AppContextFromScript {
  param([string]$Path)
  $content = Get-Content -LiteralPath $Path -Raw

  $hasRevenueCycle = ($content -match '(?i)\bRevenueCycle\b')
  $hasAppbar = ($content -match '(?i)\bAppbar\b' -or $content -match '(?i)Icon_AppBar')
  $hasPathNet = ($content -match '(?i)\bPathNet/')
  $hasPowerChart = ($content -match '(?i)Icon_Powerchart' -or $content -match '(?i)\bMIL/Powerchart\b')

  if ($hasRevenueCycle) { return "RevenueCycle" }
  if ($hasAppbar -and $hasPathNet) { return "AppbarPathNet" }
  if ($hasPowerChart) { return "PowerChart" }
  return "Unknown"
}

function Get-NormalizedExitKey {
  param([string]$AppContext)
  if ($AppContext -eq "RevenueCycle") { return "f" }
  if ($AppContext -eq "PowerChart" -or $AppContext -eq "AppbarPathNet") { return "t" }
  return ""
}

function Invoke-ExitAutoFixes {
  param(
    [string]$Path,
    [string]$AppContext
  )

  $exitKey = Get-NormalizedExitKey -AppContext $AppContext
  if ([string]::IsNullOrWhiteSpace($exitKey)) {
    return [pscustomobject]@{
      Changed = $false
      ReplacedTaskExitLines = @()
    }
  }

  $lines = Get-Content -LiteralPath $Path
  $updated = New-Object System.Collections.Generic.List[string]
  $replaced = @()

  for ($i = 0; $i -lt $lines.Count; $i++) {
    $line = $lines[$i]
    if ($line -match '^(?<indent>[ \t]*)"MIL/MenuSearch"\.SelectMenuSubMenu "Task","Exit"\s*$') {
      $indent = $Matches.indent
      $updated.Add($indent + 'TypeText altKey')
      $updated.Add($indent + 'wait 2')
      $updated.Add($indent + ('TypeText "{0}"' -f $exitKey))
      $updated.Add($indent + 'wait 2')
      $updated.Add($indent + 'TypeText "x"')
      $replaced += ($i + 1)
      continue
    }
    $updated.Add($line)
  }

  if ($replaced.Count -gt 0) {
    Set-Content -LiteralPath $Path -Value @($updated) -Encoding Default
  }

  return [pscustomobject]@{
    Changed = ($replaced.Count -gt 0)
    ReplacedTaskExitLines = @($replaced)
  }
}

function Get-ShortcutMap {
  param(
    [string]$CsvPath,
    [string]$Prefix,
    [switch]$AllowDgAlias
  )

  $map = @{}
  if (-not (Test-Path -LiteralPath $CsvPath)) { return $map }

  $rows = Import-Csv -LiteralPath $CsvPath
  foreach ($row in $rows) {
    $appName = [string]$row.AppName
    $shortcut = [string]$row.citrixShortcut
    if ([string]::IsNullOrWhiteSpace($appName) -or [string]::IsNullOrWhiteSpace($shortcut)) { continue }

    $token = $appName
    if (-not [string]::IsNullOrWhiteSpace($Prefix)) {
      $prefixRegex = '^' + [regex]::Escape($Prefix)
      $token = [regex]::Replace($token, $prefixRegex, '', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    }

    $norm = Normalize-AppToken -Value $token
    if (-not [string]::IsNullOrWhiteSpace($norm) -and -not $map.ContainsKey($norm)) {
      $map[$norm] = $shortcut
    }

    if ($AllowDgAlias -and $token -match '^(?i)DG_(.+)$') {
      $aliasNorm = Normalize-AppToken -Value $Matches[1]
      if (-not [string]::IsNullOrWhiteSpace($aliasNorm) -and -not $map.ContainsKey($aliasNorm)) {
        $map[$aliasNorm] = $shortcut
      }
    }
  }
  return $map
}

function Invoke-ScriptAutoFixes {
  param(
    [string]$Path,
    [string]$Workflow
  )

  $lines = Get-Content -LiteralPath $Path
  $updatedLines = @()
  $spellingFixedLines = @()
  $separatorFixedLines = @()
  $legacyRemovedLines = @()
  $searchRectFixedLines = @()

  for ($i = 0; $i -lt $lines.Count; $i++) {
    $line = $lines[$i]
    $lineNumber = $i + 1

    if ($line -match '^\s*TEST CASE NAME:\s*.+$' -and -not [string]::IsNullOrWhiteSpace($Workflow)) {
      $line = "TEST CASE NAME: $Workflow"
    }
    if ($line -match '^\s*Set wfName = ".*"$' -and -not [string]::IsNullOrWhiteSpace($Workflow)) {
      $line = "Set wfName = `"$Workflow`""
    }

    # Remove known legacy commented scaffolding lines automatically.
    if ($line -match '^[ \t]*\(\*Set common to JSONValue\(file ResourcePath\("testdata\.json"\)\)[ \t]*$' -or
        $line -match '^[ \t]*Set testData to JSONValue\(file ResourcePath\("RevenueCycle\.json"\)\)\*\)[ \t]*$' -or
        $line -match '^[ \t]*\(\*set the remoteworkinterval to 2[ \t]*$' -or
        $line -match '^[ \t]*set CitrixCredentials to "UTIL/Credential"\.retrieveCredential \(citrixCredentialID\)\*\)[ \t]*$' -or
        $line -match '^[ \t]*\(\*if Platform is empty then set platform to platform[ \t]*$' -or
        $line -match '^[ \t]*if appDomainName is empty then set appDomainName to appDomainName[ \t]*$' -or
        $line -match '^[ \t]*if millenniumDomain is empty then set millenniumDomain to millenniumDomain\*\)[ \t]*$' -or
        $line -match '^[ \t]*//Run "UTIL/Common"\.cleanupSelectedPlatform platform[ \t]*$' -or
        $line -match '^[ \t]*StartMovie\b' -or
        $line -match '^[ \t]*StopMovie\b' -or
        $line -match '^[ \t]*Run "VA_Common_Workflows"\.beginScript\b' -or
        $line -match '^[ \t]*Run "VA_Common_Workflows"\.endScript\b' -or
        $line -match '^[ \t]*"DSK/Utilities"\.dismissRulesOfRoad\b' -or
        $line -match '^[ \t]*Params platform, appDomainName, millenniumDomain\b' -or
        $line -match '^[ \t]*if platform is empty then set platform to\b' -or
        $line -match '^[ \t]*if appDomainName is empty then set appDomainName to\b' -or
        $line -match '^[ \t]*if millenniumDomain is empty then set millenniumDomain to\b' -or
        $line -match '\bLogSuccess\b' -or
        $line -match '\bselectPlatform\b' -or
        $line -match '\bloginExe\b' -or
        $line -match '^[ \t]*//.*\b(StartMovie|StopMovie|dismissRulesOfRoad|selectPlatform|loginExe|beginScript|endScript)\b') {
      $legacyRemovedLines += $lineNumber
      continue
    }

    $separatorFixedInLine = $false
    if ($line -match '^(?<indent>[ \t]*)\((?<eq>=+)\*\)[ \t]*$') {
      $line = "$($Matches.indent)(*$($Matches.eq)*)"
      $separatorFixedInLine = $true
    } elseif ($line -match '^(?<indent>[ \t]*)\(\*(?<eq>=+)\)[ \t]*$') {
      $line = "$($Matches.indent)(*$($Matches.eq)*)"
      $separatorFixedInLine = $true
    } elseif ($line -match '^(?<indent>[ \t]*)\((?<eq>=+)\)[ \t]*$') {
      $line = "$($Matches.indent)(*$($Matches.eq)*)"
      $separatorFixedInLine = $true
    }

    $spellingFixedInLine = $false
    if ($line -imatch '\bSerachRectangle\b') {
      $line = [regex]::Replace($line, "\bSerachRectangle\b", "SearchRectangle", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
      $spellingFixedInLine = $true
    }

    $searchRectFixedInLine = $false
    if ($line -match 'SearchRectangle:\s*"UTIL/Screen"\.TopLef\b') {
      $line = [regex]::Replace($line, 'SearchRectangle:\s*"UTIL/Screen"\.TopLef\b', 'SearchRectangle:"UTIL/Screen".TopLeft')
      $searchRectFixedInLine = $true
    }

    if ($line -match '\bCaptureScreen\b') {
      # Keep CaptureScreen only inside catch/recovery.
      $isInCatch = $false
      for ($k = 0; $k -lt $i; $k++) {
        $trim = $lines[$k].Trim()
        if ($trim -match '^catch\s+exception\b') { $isInCatch = $true }
        if ($trim -match '^end\s+try\b') { $isInCatch = $false }
      }
      if (-not $isInCatch) {
        $legacyRemovedLines += $lineNumber
        continue
      }
    }

    if ($spellingFixedInLine) { $spellingFixedLines += $lineNumber }
    if ($searchRectFixedInLine) { $searchRectFixedLines += $lineNumber }
    if ($separatorFixedInLine) { $separatorFixedLines += $lineNumber }
    $updatedLines += $line
  }

  if ($spellingFixedLines.Count -gt 0 -or $separatorFixedLines.Count -gt 0 -or $legacyRemovedLines.Count -gt 0 -or $searchRectFixedLines.Count -gt 0) {
    Set-Content -LiteralPath $Path -Value $updatedLines -Encoding Default
  }

  return [pscustomobject]@{
    SpellingFixedLines = @($spellingFixedLines)
    SeparatorFixedLines = @($separatorFixedLines)
    LegacyRemovedLines = @($legacyRemovedLines)
    SearchRectFixedLines = @($searchRectFixedLines)
  }
}

function Invoke-DataLoaderAutoFixes {
  param(
    [string]$Path,
    [hashtable]$Dh2ShortcutMap,
    [hashtable]$FedaShortcutMap
  )

  if (-not (Test-Path -LiteralPath $Path)) {
    return [pscustomobject]@{
      Changed = $false
      LegacyRemovedLines = @()
      NormalizedLines = @()
      Dh2CommentedLines = @()
      FedaActivatedLines = @()
    }
  }

  $lines = Get-Content -LiteralPath $Path
  $updated = @()
  $legacyRemoved = @()
  $normalized = @()
  $dh2Commented = @()
  $fedaActivated = @()
  $inDh2 = $false
  $inFeda = $false
  $inPerfDataGuard = $false
  $inFunctionalBranch = $false
  $appTokens = @{}

  foreach ($line in $lines) {
    if ($line -match '^\s*Set\s+citrixApp(?<idx>\d*)\s*=\s*"(?<value>[^"]*)"') {
      $idx = $Matches.idx
      if ([string]::IsNullOrWhiteSpace($idx)) { $idx = "" }
      $appTokens[$idx] = $Matches.value
    }
  }

  for ($i = 0; $i -lt $lines.Count; $i++) {
    $line = $lines[$i]
    $lineNumber = $i + 1

    if ($line -match '^\s*If \(the number of keys in performance_data is 0\)\s*$') {
      $inPerfDataGuard = $true
      $inFunctionalBranch = $true
      $inDh2 = $false
      $inFeda = $false
    } elseif ($inPerfDataGuard -and $line -match '^\s*Else\s*$') {
      $inFunctionalBranch = $false
      $inDh2 = $false
      $inFeda = $false
    } elseif ($inPerfDataGuard -and $line -match '^\s*End If\s*$') {
      $inPerfDataGuard = $false
      $inFunctionalBranch = $false
      $inDh2 = $false
      $inFeda = $false
    }


    if ($inFunctionalBranch -and $line -match '^\s*//\s*DH2 Credentials') { $inDh2 = $true; $inFeda = $false }
    if ($inFunctionalBranch -and $line -match '^\s*//\s*SUT CREDs:\s*FEDA') { $inFeda = $true; $inDh2 = $false }

    if ($line -match '^\s*Params platform, appDomainName, millenniumDomain\b' -or
        $line -match '^\s*if platform is empty then set platform to\b' -or
        $line -match '^\s*if appDomainName is empty then set appDomainName to\b' -or
        $line -match '^\s*if millenniumDomain is empty then set millenniumDomain to\b' -or
        $line -match '^\s*set domain\s*=' -or
        $line -match '^\s*set citrixURL\s*=' -or
        $line -match '^\s*set citrixCredentialID\s*=') {
      $legacyRemoved += $lineNumber
      continue
    }

    if ($line -match 'Powerchart\.exe') {
      $line = $line -replace 'Powerchart\.exe', 'PowerChart'
      $normalized += $lineNumber
    }
    if ($line -match 'Put performance_data\.Powerchart into citrixShortcut') {
      $line = $line -replace 'Put performance_data\.Powerchart into citrixShortcut', 'Put performance_data.PowerChart into citrixShortcut'
      $normalized += $lineNumber
    }

    if ($inFunctionalBranch -and $inDh2 -and $line -match '^\s*Set\s+(sutUsername|sutPassword|citrixShortcut)\s*=') {
      $line = $line -replace '^(\s*)', '$1//'
      $dh2Commented += $lineNumber
    }
    if ($inFunctionalBranch -and $inFeda -and $line -match '^\s*//\s*Set\s+(sutUsername|sutPassword|citrixShortcut)\s*=') {
      $line = $line -replace '^(\s*)//\s*', '$1'
      $fedaActivated += $lineNumber
    }

    if ($inFunctionalBranch -and $inDh2 -and $line -match '^\s*//\s*Set\s+citrixShortcut(?<idx>\d*)\s*=\s*"(?<value>[^"]*)"') {
      $idx = $Matches.idx
      if ([string]::IsNullOrWhiteSpace($idx)) { $idx = "" }
      $existingValue = $Matches.value
      $appValue = ""
      if ($appTokens.ContainsKey($idx)) { $appValue = $appTokens[$idx] }
      elseif ($appTokens.ContainsKey("")) { $appValue = $appTokens[""] }
      $mapped = ""
      $appNorm = Normalize-AppToken -Value $appValue
      if (-not [string]::IsNullOrWhiteSpace($appNorm) -and $Dh2ShortcutMap.ContainsKey($appNorm)) {
        $mapped = [string]$Dh2ShortcutMap[$appNorm]
      } elseif (-not [string]::IsNullOrWhiteSpace($existingValue)) {
        $mapped = $existingValue
      }
      $line = [regex]::Replace($line, '"[^"]*"\s*$', ('"' + $mapped + '"'))
    }

    if ($inFunctionalBranch -and $inFeda -and $line -match '^\s*Set\s+citrixShortcut(?<idx>\d*)\s*=\s*"(?<value>[^"]*)"') {
      $idx = $Matches.idx
      if ([string]::IsNullOrWhiteSpace($idx)) { $idx = "" }
      $existingValue = $Matches.value
      $appValue = ""
      if ($appTokens.ContainsKey($idx)) { $appValue = $appTokens[$idx] }
      elseif ($appTokens.ContainsKey("")) { $appValue = $appTokens[""] }
      $mapped = ""
      $appNorm = Normalize-AppToken -Value $appValue
      if (-not [string]::IsNullOrWhiteSpace($appNorm) -and $FedaShortcutMap.ContainsKey($appNorm)) {
        $mapped = [string]$FedaShortcutMap[$appNorm]
      } elseif (-not [string]::IsNullOrWhiteSpace($existingValue)) {
        $mapped = $existingValue
      }
      $line = [regex]::Replace($line, '"[^"]*"\s*$', ('"' + $mapped + '"'))
    }

    $updated += $line
  }

  $changed = ($legacyRemoved.Count -gt 0 -or $normalized.Count -gt 0 -or $dh2Commented.Count -gt 0 -or $fedaActivated.Count -gt 0)
  if ($changed) {
    Set-Content -LiteralPath $Path -Value $updated -Encoding Default
  }

  return [pscustomobject]@{
    Changed = $changed
    LegacyRemovedLines = @($legacyRemoved)
    NormalizedLines = @($normalized)
    Dh2CommentedLines = @($dh2Commented)
    FedaActivatedLines = @($fedaActivated)
  }
}

function Get-LoaderDefaultValue {
  param([string]$Path, [string]$VariableName)
  $pattern = '^\s*Set\s+' + [regex]::Escape($VariableName) + '\s*=\s*"(?<value>[^"]*)"'
  foreach ($record in (Get-ActiveLineRecords -Path $Path)) {
    if ($record.Active -match $pattern) { return $Matches["value"] }
  }
  return ""
}

function Get-LoaderMillCredentialDefaults {
  param([string]$Path)

  $map = [ordered]@{}
  if (-not (Test-Path -LiteralPath $Path)) { return $map }

  foreach ($record in (Get-ActiveLineRecords -Path $Path)) {
    if ($record.Active -match '^\s*Set\s+(?<name>millUsername\d*)\s*=\s*"(?<value>[^"]*)"') {
      $name = $Matches["name"]
      if (-not $map.Contains($name)) {
        $map[$name] = $Matches["value"]
      }
    }
  }

  if ($map.Count -eq 0) {
    $millUsername = Get-LoaderDefaultValue -Path $Path -VariableName "millUsername"
    if (-not [string]::IsNullOrWhiteSpace($millUsername)) {
      $map["millUsername"] = $millUsername
    }
  }

  $millPassword = Get-LoaderDefaultValue -Path $Path -VariableName "millPassword"
  if (-not [string]::IsNullOrWhiteSpace($millPassword)) {
    $map["millPassword"] = $millPassword
  }

  return $map
}

function Get-LoaderFinDefaults {
  param([string]$Path)

  $finMap = [ordered]@{}
  if (-not (Test-Path -LiteralPath $Path)) { return $finMap }

  foreach ($record in (Get-ActiveLineRecords -Path $Path)) {
    if ($record.Active -match '^\s*Set\s+(?<name>[A-Za-z_][A-Za-z0-9_]*)\s*=\s*"(?<value>[^"]*)"') {
      $name = $Matches["name"]
      $value = $Matches["value"]
      if ($name -imatch 'fin' -and -not $finMap.Contains($name)) {
        $finMap[$name] = $value
      }
    }
  }

  return $finMap
}

function Sync-CsvValues {
  param(
    [string]$Path,
    [System.Collections.IDictionary]$ValuesByHeader
  )

  if ($null -eq $ValuesByHeader -or $ValuesByHeader.Count -eq 0) {
    return [pscustomobject]@{
      Path = $Path
      UpdatedLines = @()
      Headers = @()
      Applied = $false
    }
  }

  $headers = @()
  $values = @()
  if (Test-Path -LiteralPath $Path) {
    $existing = @(Get-Content -LiteralPath $Path)
    if ($existing.Count -gt 0) { $headers = @(Split-CsvFields -Line $existing[0]) }
    if ($existing.Count -gt 1) { $values = @(Split-CsvFields -Line $existing[1]) }
  }

  if ($headers.Count -eq 0) {
    $headers = @($ValuesByHeader.Keys)
    $values = @()
  }

  $headerIndex = @{}
  for ($i = 0; $i -lt $headers.Count; $i++) {
    $headerIndex[$headers[$i]] = $i
  }

  foreach ($key in $ValuesByHeader.Keys) {
    if (-not $headerIndex.ContainsKey($key)) {
      $headerIndex[$key] = $headers.Count
      $headers += $key
    }
  }

  $normalizedValues = New-Object System.Collections.Generic.List[string]
  for ($i = 0; $i -lt $headers.Count; $i++) {
    if ($i -lt $values.Count) { $normalizedValues.Add([string]$values[$i]) }
    else { $normalizedValues.Add('') }
  }

  foreach ($key in $ValuesByHeader.Keys) {
    $idx = [int]$headerIndex[$key]
    $normalizedValues[$idx] = [string]$ValuesByHeader[$key]
  }

  $content = @(
    (Join-CsvFields -Fields $headers),
    (Join-CsvFields -Fields @($normalizedValues))
  )
  Set-Content -LiteralPath $Path -Value $content -Encoding Default

  return [pscustomobject]@{
    Path = $Path
    UpdatedLines = @(1,2)
    Headers = @($ValuesByHeader.Keys)
    Applied = $true
  }
}

function Ensure-WorkflowCsvFinValues {
  param(
    [string]$Path,
    [System.Collections.IDictionary]$FinDefaults
  )

  if ($null -eq $FinDefaults -or $FinDefaults.Count -eq 0) {
    return [pscustomobject]@{
      Path = $Path
      UpdatedLines = @()
      Headers = @()
      Applied = $false
    }
  }

  return Sync-CsvValues -Path $Path -ValuesByHeader $FinDefaults
}

function Ensure-CsvFromHeadersAndValues {
  param(
    [string]$Path,
    [string[]]$Headers,
    [string[]]$Values
  )
  $content = @(
    (Join-CsvFields -Fields $Headers),
    (Join-CsvFields -Fields $Values)
  )
  Set-Content -LiteralPath $Path -Value $content -Encoding Default
  return [pscustomobject]@{
    Path = $Path
    UpdatedLines = @(1,2)
  }
}

function Get-NormalizedWorkflowName {
  param([string]$Name)
  if ([string]::IsNullOrWhiteSpace($Name)) { return $Name }
  return ([regex]::Replace($Name.Trim(), '\s+', '-'))
}

function Rename-AssociatedWorkflowFiles {
  param(
    [string]$Root,
    [string]$OriginalWorkflow,
    [string]$NormalizedWorkflow
  )

  $renamed = @()
  if ([string]::IsNullOrWhiteSpace($OriginalWorkflow) -or $OriginalWorkflow -eq $NormalizedWorkflow) {
    return [pscustomobject]@{
      Workflow = $NormalizedWorkflow
      Renamed = @()
    }
  }

  $pairs = @(
    [pscustomobject]@{
      Old = Join-Path $Root ("Scripts\{0}.script" -f $OriginalWorkflow)
      New = Join-Path $Root ("Scripts\{0}.script" -f $NormalizedWorkflow)
    },
    [pscustomobject]@{
      Old = Join-Path $Root ("Scripts\DataLoader\{0}_DataLoader.script" -f $OriginalWorkflow)
      New = Join-Path $Root ("Scripts\DataLoader\{0}_DataLoader.script" -f $NormalizedWorkflow)
    },
    [pscustomobject]@{
      Old = Join-Path $Root ("Resources\{0}_LoginData.csv" -f $OriginalWorkflow)
      New = Join-Path $Root ("Resources\{0}_LoginData.csv" -f $NormalizedWorkflow)
    },
    [pscustomobject]@{
      Old = Join-Path $Root ("Resources\{0}_WorkflowData.csv" -f $OriginalWorkflow)
      New = Join-Path $Root ("Resources\{0}_WorkflowData.csv" -f $NormalizedWorkflow)
    }
  )

  foreach ($pair in $pairs) {
    if (-not (Test-Path -LiteralPath $pair.Old)) { continue }
    if ($pair.Old -eq $pair.New) { continue }
    if (Test-Path -LiteralPath $pair.New) {
      throw ("Cannot normalize workflow filename from '{0}' to '{1}' because destination already exists: {2}" -f $OriginalWorkflow, $NormalizedWorkflow, $pair.New)
    }
    Rename-Item -LiteralPath $pair.Old -NewName (Split-Path -Leaf $pair.New)
    $renamed += [pscustomobject]@{
      Old = $pair.Old
      New = $pair.New
    }
  }

  return [pscustomobject]@{
    Workflow = $NormalizedWorkflow
    Renamed = @($renamed)
  }
}

$root = (Resolve-Path -LiteralPath $SuiteRoot).Path
$requestedWorkflow = $Workflow
$normalizedWorkflow = Get-NormalizedWorkflowName -Name $Workflow
$workflowRenameInfo = Rename-AssociatedWorkflowFiles -Root $root -OriginalWorkflow $requestedWorkflow -NormalizedWorkflow $normalizedWorkflow
$Workflow = $workflowRenameInfo.Workflow
$workflowRenamedPaths = @($workflowRenameInfo.Renamed)
$skillRoot = Split-Path -Parent $PSScriptRoot
$ablfhirMapCsv = Join-Path $skillRoot "ABLFHIR_CitrixShortcuts.csv"
$ablfedaMapCsv = Join-Path $skillRoot "ABLFEDA_CitrixShortcuts.csv"
$dh2ShortcutMap = Get-ShortcutMap -CsvPath $ablfhirMapCsv -Prefix "ABLFHIR_"
$fedaShortcutMap = Get-ShortcutMap -CsvPath $ablfedaMapCsv -Prefix "ABLFEDA_" -AllowDgAlias
$scriptPath = Join-Path $root ("Scripts\{0}.script" -f $Workflow)
$dataLoaderPath = Join-Path $root ("Scripts\DataLoader\{0}_DataLoader.script" -f $Workflow)
$loginCsv = Join-Path $root ("Resources\{0}_LoginData.csv" -f $Workflow)
$workflowCsv = Join-Path $root ("Resources\{0}_WorkflowData.csv" -f $Workflow)

if (-not (Test-Path -LiteralPath $scriptPath)) { throw "Missing script: $scriptPath" }
$appContext = Get-AppContextFromScript -Path $scriptPath

$spellingFixedLines = @()
$separatorFixedLines = @()
$legacyRemovedLines = @()
$searchRectFixedLines = @()
$exitFixes = $null
$loaderFixes = $null
$csvFixes = @()
if ($ConversionMode -eq "On") {
  $autoFixResults = Invoke-ScriptAutoFixes -Path $scriptPath -Workflow $Workflow
  $spellingFixedLines = @($autoFixResults.SpellingFixedLines)
  $separatorFixedLines = @($autoFixResults.SeparatorFixedLines)
  $legacyRemovedLines = @($autoFixResults.LegacyRemovedLines)
  $searchRectFixedLines = @($autoFixResults.SearchRectFixedLines)

  $exitFixes = Invoke-ExitAutoFixes -Path $scriptPath -AppContext $appContext

  $loaderFixes = Invoke-DataLoaderAutoFixes -Path $dataLoaderPath -Dh2ShortcutMap $dh2ShortcutMap -FedaShortcutMap $fedaShortcutMap

  if (Test-Path -LiteralPath $dataLoaderPath) {
    $millDefaults = Get-LoaderMillCredentialDefaults -Path $dataLoaderPath
    $finDefaults = Get-LoaderFinDefaults -Path $dataLoaderPath

    $loginCsvFix = Sync-CsvValues -Path $loginCsv -ValuesByHeader $millDefaults
    if ($loginCsvFix.Applied) {
      $csvFixes += $loginCsvFix
    }
    $workflowCsvFix = Ensure-WorkflowCsvFinValues -Path $workflowCsv -FinDefaults $finDefaults
    if ($workflowCsvFix.Applied) {
      $csvFixes += $workflowCsvFix
    }
  }
}

$legacyPattern = "StartMovie|StopMovie|dismissRulesOfRoad|selectPlatform|loginExe|Params platform|appDomainName|millenniumDomain|beginScript|endScript|LogSuccess|Set common to JSONValue|Set testData to JSONValue|set the remoteworkinterval to 2|set CitrixCredentials to ""UTIL/Credential""\.retrieveCredential|if Platform is empty then set platform to platform|cleanupSelectedPlatform platform"
$legacyHits = @(Get-RgHits -Pattern $legacyPattern -Path $scriptPath)

$spellingPattern = "\bSerachRectangle\b"
$spellingHits = @(Get-RgHits -Pattern $spellingPattern -Path $scriptPath -IgnoreCase)
$topLefPattern = 'SearchRectangle:\s*"UTIL/Screen"\.TopLef\b'
$topLefHits = @(Get-RgHits -Pattern $topLefPattern -Path $scriptPath)
$separatorIssues = @(Test-MalformedSeparatorComments -Path $scriptPath)
$wfBodyIndentIssues = @(Test-WfTestCaseBodyIndentation -Path $scriptPath)
$ifElseIndentIssues = @(Test-IfElseIndentationInWfTestCase -Path $scriptPath)
$captureHits = @(Get-RgHits -Pattern "CaptureScreen" -Path $scriptPath)
$launchPattern = 'SCL_LaunchAndLoginCitrix\s+citrixShortcut\d*\s*,\s*sutUsername\d*\s*,\s*sutPassword\d*'
$launchHits = @(Get-RgHits -Pattern $launchPattern -Path $scriptPath)
$millLoginPattern = 'Run "MIL/Millennium"\.login\s+millUsername\d*\s*,\s*millPassword\d*'
$millLoginHits = @(Get-RgHits -Pattern $millLoginPattern -Path $scriptPath)
$taskExitHits = @(Get-RgHits -Pattern '"MIL/MenuSearch"\.SelectMenuSubMenu "Task","Exit"' -Path $scriptPath)
$altKeyHits = @(Get-RgHits -Pattern 'TypeText altKey' -Path $scriptPath)
$tKeyHits = @(Get-RgHits -Pattern 'TypeText "t"' -Path $scriptPath)
$fKeyHits = @(Get-RgHits -Pattern 'TypeText "f"' -Path $scriptPath)
$xKeyHits = @(Get-RgHits -Pattern 'TypeText "x"' -Path $scriptPath)
$scriptContentLines = @((Get-ActiveLineRecords -Path $scriptPath) | Select-Object -ExpandProperty Active)
$testCaseNameHits = @($scriptContentLines | Where-Object { $_ -match ('^\s*TEST CASE NAME:\s*' + [regex]::Escape($Workflow) + '\s*$') })
$wfNameHits = @($scriptContentLines | Where-Object { $_ -match ('^\s*Set wfName = "' + [regex]::Escape($Workflow) + '"\s*$') })

$dataLoaderMissing = -not (Test-Path -LiteralPath $dataLoaderPath)
$loaderLegacyPattern = "Params platform|appDomainName|millenniumDomain|selectPlatform|loginExe|domain|citrixURL|citrixCredentialID"
$loaderLegacyHits = @()
$loaderDh2Commented = $false
$loaderFedaActive = $false
$loaderPerformanceHits = @()
$loaderIfElseGuardOk = $false

if (-not $dataLoaderMissing) {
  $loaderLegacyHits = @(Get-RgHits -Pattern $loaderLegacyPattern -Path $dataLoaderPath)
  $loaderDh2Commented = ((Get-Count -Pattern '^\s*//\s*Set\s+sutUsername\s*=' -Path $dataLoaderPath -IncludeComments) -gt 0) -and `
                        ((Get-Count -Pattern '^\s*//\s*Set\s+sutPassword\s*=' -Path $dataLoaderPath -IncludeComments) -gt 0)
  $loaderFedaActive = ((Get-Count -Pattern '^\s*Set\s+sutUsername\s*=' -Path $dataLoaderPath) -gt 0) -and `
                      ((Get-Count -Pattern '^\s*Set\s+sutPassword\s*=' -Path $dataLoaderPath) -gt 0)
  $loaderPerformanceHits += @(Get-RgHits -Pattern 'Put performance_data\.sutUsername' -Path $dataLoaderPath)
  $loaderPerformanceHits += @(Get-RgHits -Pattern 'Put performance_data\.sutPassword' -Path $dataLoaderPath)
  $loaderPerformanceHits += @(Get-RgHits -Pattern 'Put performance_data\.millUsername' -Path $dataLoaderPath)
  $loaderPerformanceHits += @(Get-RgHits -Pattern 'Put performance_data\.millPassword' -Path $dataLoaderPath)
  $hasPerfIf = (Get-Count -Pattern '^\s*If \(the number of keys in performance_data is 0\)' -Path $dataLoaderPath) -ge 1
  $hasElse = (Get-Count -Pattern '^\s*Else\s*$' -Path $dataLoaderPath) -ge 1
  $hasEndIf = (Get-Count -Pattern '^\s*End If\s*$' -Path $dataLoaderPath) -ge 1
  $loaderIfElseGuardOk = $hasPerfIf -and $hasElse -and $hasEndIf
}

$loginCsvInfo = Get-CsvInfo -Path $loginCsv
$workflowCsvInfo = Get-CsvInfo -Path $workflowCsv
$csvPresent = $loginCsvInfo.Exists -and $workflowCsvInfo.Exists
$csvShapeOk = ($loginCsvInfo.DataCount -eq 1) -and ($workflowCsvInfo.DataCount -eq 1)
$csvColumnsOk = (-not $loginCsvInfo.ColumnMismatch) -and (-not $workflowCsvInfo.ColumnMismatch)
$loginHeaderOk = (@($loginCsvInfo.Headers | Where-Object { $_ -match '^millUsername\d*$' }).Count -ge 1) -and `
                 (@($loginCsvInfo.Headers | Where-Object { $_ -match '^millPassword\d*$' }).Count -ge 1)
$workflowHeaderOk = $workflowCsvInfo.HeaderCount -ge 1

$wfTestCaseCount = Get-Count -Pattern "wfTestCase" -Path $scriptPath
$endTestCaseCount = Get-Count -Pattern "EndTestCase wfStep" -Path $scriptPath
$catchCount = Get-Count -Pattern "catch exception" -Path $scriptPath
$scaleRecoveryCount = Get-Count -Pattern "ScaleRecovery" -Path $scriptPath
$scriptRecords = @(Get-ActiveLineRecords -Path $scriptPath)
$scriptLines = @($scriptRecords | Select-Object -ExpandProperty Active)
$scaleRecoveryAll = @()
$scaleRecoveryPreCatch = @()
$scaleRecoveryInCatch = @()
$scaleRecoveryOther = @()
$inCatchBlock = $false
for ($i = 0; $i -lt $scriptLines.Count; $i++) {
  $line = $scriptLines[$i]
  $trimmed = $line.Trim()
  if ($trimmed -match '^catch\s+exception\b') {
    $inCatchBlock = $true
    continue
  }
  if ($trimmed -match '^end\s+try\b') {
    $inCatchBlock = $false
  }
  if ($line -match 'Run "CTX/AbilitiesCitrixMethods"\.ScaleRecovery') {
    $scaleRecoveryAll += ($i + 1)
    if ($inCatchBlock) {
      $scaleRecoveryInCatch += ($i + 1)
      continue
    }
    $nextSig = ""
    for ($j = $i + 1; $j -lt $scriptLines.Count; $j++) {
      $candidate = $scriptLines[$j].Trim()
      if (Test-IsFormattingLine -Line $scriptLines[$j]) {
        continue
      }
      $nextSig = $candidate
      break
    }
    if ($nextSig -match '^catch\s+exception\b') {
      $scaleRecoveryPreCatch += ($i + 1)
    } else {
      $scaleRecoveryOther += ($i + 1)
    }
  }
}

$failed = $false
$verboseFailures = ($FailureMode -eq "Verbose")

Write-Host "Workflow: $Workflow"
if ($requestedWorkflow -ne $Workflow) {
  Write-Host ("[CONVERT] Normalized workflow filename spaces to hyphens: '{0}' -> '{1}'." -f $requestedWorkflow, $Workflow)
  if ($workflowRenamedPaths.Count -gt 0) {
    foreach ($item in $workflowRenamedPaths) {
      Write-Host ("[CONVERT] Renamed associated file: {0} -> {1}" -f $item.Old, $item.New)
    }
  }
}
Write-Host "Script: $scriptPath"
Write-Host ("ConversionMode={0}" -f $ConversionMode)
Write-Host ""
Write-Host ("wfTestCase={0} EndTestCase={1}" -f $wfTestCaseCount, $endTestCaseCount)
Write-Host ("catch exception hits={0} ScaleRecovery hits={1}" -f $catchCount, $scaleRecoveryCount)
Write-Host ("ScaleRecovery placement: pre-catch={0} in-catch={1}" -f $scaleRecoveryPreCatch.Count, $scaleRecoveryInCatch.Count)
Write-Host ("DataLoader present={0}" -f (-not $dataLoaderMissing))
Write-Host ("CSV present (LoginData/WorkflowData)={0}" -f $csvPresent)
Write-Host ("Detected app context={0}" -f $appContext)
Write-Host ""

if ($spellingFixedLines.Count -gt 0) {
  Write-Host ("[CONVERT] Replaced SerachRectangle -> SearchRectangle ({0} line(s))." -f $spellingFixedLines.Count)
  Write-Host ("[CONVERT] Spelling fixed at line(s): {0}" -f (($spellingFixedLines | Sort-Object -Unique) -join ', '))
} else {
  Write-Host "[CONVERT] No SearchRectangle spelling conversions applied."
}

if ($searchRectFixedLines.Count -gt 0) {
  Write-Host ("[CONVERT] Replaced SearchRectangle TopLef -> TopLeft ({0} line(s))." -f $searchRectFixedLines.Count)
  Write-Host ("[CONVERT] SearchRectangle TopLeft fixed at line(s): {0}" -f (($searchRectFixedLines | Sort-Object -Unique) -join ', '))
} else {
  Write-Host "[CONVERT] No SearchRectangle TopLef conversions applied."
}

if ($separatorFixedLines.Count -gt 0) {
  Write-Host ("[CONVERT] Normalized malformed separator comments ({0} line(s))." -f $separatorFixedLines.Count)
  Write-Host ("[CONVERT] Separator comments fixed at line(s): {0}" -f (($separatorFixedLines | Sort-Object -Unique) -join ', '))
} else {
  Write-Host "[CONVERT] No separator comment conversions applied."
}

if ($legacyRemovedLines.Count -gt 0) {
  Write-Host ("[CONVERT] Removed legacy commented scaffolding ({0} line(s))." -f $legacyRemovedLines.Count)
  Write-Host ("[CONVERT] Legacy scaffolding removed at line(s): {0}" -f (($legacyRemovedLines | Sort-Object -Unique) -join ', '))
} else {
  Write-Host "[CONVERT] No legacy commented scaffolding removals applied."
}

if ($null -ne $exitFixes) {
  if ($exitFixes.ReplacedTaskExitLines.Count -gt 0) {
    Write-Host ("[CONVERT] Normalized Task>Exit to key-sequence exit at line(s): {0}" -f (($exitFixes.ReplacedTaskExitLines | Sort-Object -Unique) -join ', '))
  } else {
    Write-Host "[CONVERT] No Task>Exit normalization was required."
  }
}

if ($null -ne $loaderFixes) {
  if ($loaderFixes.LegacyRemovedLines.Count -gt 0) {
    Write-Host ("[CONVERT] DataLoader removed legacy scaffolding at line(s): {0}" -f (($loaderFixes.LegacyRemovedLines | Sort-Object -Unique) -join ', '))
  } else {
    Write-Host "[CONVERT] DataLoader had no legacy scaffolding removals."
  }
  if ($loaderFixes.NormalizedLines.Count -gt 0) {
    Write-Host ("[CONVERT] DataLoader normalized values at line(s): {0}" -f (($loaderFixes.NormalizedLines | Sort-Object -Unique) -join ', '))
  } else {
    Write-Host "[CONVERT] DataLoader had no normalization replacements."
  }
  if ($loaderFixes.Dh2CommentedLines.Count -gt 0) {
    Write-Host ("[CONVERT] DataLoader commented DH2 credentials at line(s): {0}" -f (($loaderFixes.Dh2CommentedLines | Sort-Object -Unique) -join ', '))
  } else {
    Write-Host "[CONVERT] DataLoader DH2 credentials already commented."
  }
  if ($loaderFixes.FedaActivatedLines.Count -gt 0) {
    Write-Host ("[CONVERT] DataLoader activated FEDA credentials at line(s): {0}" -f (($loaderFixes.FedaActivatedLines | Sort-Object -Unique) -join ', '))
  } else {
    Write-Host "[CONVERT] DataLoader FEDA credentials already active."
  }
}

if ($csvFixes.Count -gt 0) {
  foreach ($fix in $csvFixes) {
    Write-Host ("[CONVERT] CSV synchronized: {0} (line(s): {1})" -f $fix.Path, ($fix.UpdatedLines -join ', '))
  }
}
Write-Host ""

if ($legacyHits.Count -gt 0) {
  $failed = $true
  Write-Host "[FAIL] Legacy leftovers found:"
  $legacyHits | ForEach-Object { Write-Host $_ }
  if ($verboseFailures) {
    Write-Host "  Hint: remove these unless they are required for catch/recovery diagnostics."
    Write-Host "  Hint: keep LogError/CaptureScreen only inside exception or recovery paths."
  }
} else {
  Write-Host "[OK] No legacy leftovers matched."
}

if ($spellingHits.Count -gt 0) {
  $failed = $true
  Write-Host "[FAIL] Misspelled SearchRectangle token found:"
  $spellingHits | ForEach-Object { Write-Host $_ }
  if ($verboseFailures) {
    Write-Host "  Hint: replace 'SerachRectangle' with 'SearchRectangle'."
  }
} else {
  Write-Host "[OK] No misspelled SearchRectangle tokens found."
}

if ($topLefHits.Count -gt 0) {
  $failed = $true
  Write-Host "[FAIL] Misspelled SearchRectangle target 'TopLef' found:"
  $topLefHits | ForEach-Object { Write-Host $_ }
  if ($verboseFailures) {
    Write-Host "  Hint: replace TopLef with TopLeft in SearchRectangle targets."
  }
} else {
  Write-Host "[OK] No SearchRectangle TopLef typos found."
}

if ($wfTestCaseCount -ne $endTestCaseCount) {
  $failed = $true
  Write-Host "[FAIL] wfTestCase and EndTestCase counts do not match."
  if ($verboseFailures) {
    Write-Host "  Hint: each wfTestCase must end with one EndTestCase wfStep."
    Write-Host "  Hint: look for orphan EndTestCase or executable lines between test-case boundaries."
  }
} else {
  Write-Host "[OK] wfTestCase and EndTestCase counts match."
}

if ($separatorIssues.Count -gt 0) {
  $failed = $true
  Write-Host "[FAIL] Malformed separator comments found."
  $separatorIssues | ForEach-Object { Write-Host ("  [line {0}] {1}" -f $_.Line, $_.Content) }
  if ($verboseFailures) {
    Write-Host "  Hint: separator lines must keep the exact block-comment delimiter shape: (*=====*)."
  }
} else {
  Write-Host "[OK] Separator comment delimiters are valid."
}

if ($wfBodyIndentIssues.Count -gt 0) {
  Write-Host "[WARN] wfTestCase body indentation inconsistencies found (non-blocking)."
  $wfBodyIndentIssues | ForEach-Object { Write-Host ("  [line {0}] {1}" -f $_.Line, $_.Content) }
} else {
  Write-Host "[OK] wfTestCase body indentation is consistent."
}

if ($ifElseIndentIssues.Count -gt 0) {
  $failed = $true
  Write-Host "[FAIL] If/Else indentation issues found inside wfTestCase blocks."
  $ifElseIndentIssues | ForEach-Object { Write-Host ("  [line {0}] {1}" -f $_.Line, $_.Content) }
} else {
  Write-Host "[OK] If/Else indentation alignment is valid inside wfTestCase blocks."
}

if ($catchCount -lt 1) {
  $failed = $true
  Write-Host "[FAIL] catch exception block missing."
  if ($verboseFailures) {
    Write-Host "  Hint: keep the standard try/catch ending shape in the cleaned script."
  }
} else {
  Write-Host "[OK] catch exception block present."
}

if ($captureHits.Count -gt 0) {
  $captureOutsideCatch = @()
  $inCatch = $false
  $lines = Get-Content -LiteralPath $scriptPath
  $activeRecords = @(Get-ActiveLineRecords -Path $scriptPath)
  for ($i = 0; $i -lt $lines.Count; $i++) {
    $trim = $activeRecords[$i].Active.Trim()
    if ($trim -match '^catch\s+exception\b') { $inCatch = $true }
    if ($trim -match '^end\s+try\b') { $inCatch = $false }
    if ($activeRecords[$i].Active -match 'CaptureScreen' -and -not $inCatch) {
      $captureOutsideCatch += ($i + 1)
    }
  }
  if ($captureOutsideCatch.Count -gt 0) {
    $failed = $true
    Write-Host "[FAIL] CaptureScreen found outside catch/recovery path."
    Write-Host ("  Line(s): {0}" -f ($captureOutsideCatch -join ", "))
  } else {
    Write-Host "[OK] CaptureScreen usage is limited to catch/recovery paths."
  }
} else {
  Write-Host "[OK] No CaptureScreen usage found."
}

if ($launchHits.Count -lt 1) {
  $failed = $true
  Write-Host "[FAIL] Launch block is missing SCL_LaunchAndLoginCitrix with citrixShortcut + sut credentials."
} else {
  Write-Host "[OK] Launch block uses SCL_LaunchAndLoginCitrix with citrixShortcut + sut credentials."
}

if ($millLoginHits.Count -lt 1) {
  $failed = $true
  Write-Host "[FAIL] Millennium login call using millUsername*/millPassword* not found."
} else {
  Write-Host "[OK] Millennium login call uses millUsername*/millPassword*."
}

if ($testCaseNameHits.Count -lt 1) {
  $failed = $true
  Write-Host "[FAIL] TEST CASE NAME header is not aligned with workflow name."
} else {
  Write-Host "[OK] TEST CASE NAME header matches workflow name."
}

if ($wfNameHits.Count -lt 1) {
  $failed = $true
  Write-Host "[FAIL] wfName assignment is not aligned with workflow name."
} else {
  Write-Host "[OK] wfName assignment matches workflow name."
}

$expectsPowerChartExit = ($appContext -eq "PowerChart" -or $appContext -eq "AppbarPathNet")
$expectsRevenueCycleExit = ($appContext -eq "RevenueCycle")
if (($expectsPowerChartExit -or $expectsRevenueCycleExit) -and $taskExitHits.Count -gt 0) {
  $failed = $true
  Write-Host "[FAIL] Legacy Task>Exit menu calls remain for a normalized app context."
  $taskExitHits | ForEach-Object { Write-Host $_ }
} elseif ($taskExitHits.Count -eq 0) {
  Write-Host "[OK] No legacy Task>Exit menu call remains."
}

if ($expectsPowerChartExit) {
  if ($altKeyHits.Count -lt 1 -or $tKeyHits.Count -lt 1 -or $xKeyHits.Count -lt 1) {
    $failed = $true
    Write-Host "[FAIL] Expected normalized PowerChart/Appbar-PathNet exit key sequence (alt -> t -> x) not found."
  } else {
    Write-Host "[OK] PowerChart/Appbar-PathNet exit key sequence markers are present."
  }
}
if ($expectsRevenueCycleExit) {
  if ($altKeyHits.Count -lt 1 -or $fKeyHits.Count -lt 1 -or $xKeyHits.Count -lt 1) {
    $failed = $true
    Write-Host "[FAIL] Expected normalized RevenueCycle exit key sequence (alt -> f -> x) not found."
  } else {
    Write-Host "[OK] RevenueCycle exit key sequence markers are present."
  }
}

if ($scaleRecoveryCount -ne 2) {
  $failed = $true
  Write-Host "[FAIL] Expected exactly two ScaleRecovery hits total."
  Write-Host ("  Observed ScaleRecovery line(s): {0}" -f ($(if ($scaleRecoveryAll.Count -gt 0) { $scaleRecoveryAll -join ", " } else { "<none>" })))
  if ($verboseFailures) {
    Write-Host "  Hint: include ScaleRecovery exactly once before catch and exactly once inside catch after exception handling."
  }
} elseif ($scaleRecoveryPreCatch.Count -ne 1 -or $scaleRecoveryInCatch.Count -ne 1) {
  $failed = $true
  Write-Host "[FAIL] ScaleRecovery placement is invalid."
  Write-Host ("  Observed line(s) pre-catch={0}; in-catch={1}; other={2}" -f (
    $(if ($scaleRecoveryPreCatch.Count -gt 0) { $scaleRecoveryPreCatch -join ", " } else { "<none>" }),
    $(if ($scaleRecoveryInCatch.Count -gt 0) { $scaleRecoveryInCatch -join ", " } else { "<none>" }),
    $(if ($scaleRecoveryOther.Count -gt 0) { $scaleRecoveryOther -join ", " } else { "<none>" })
  ))
  if ($verboseFailures) {
    Write-Host "  Hint: do not place ScaleRecovery after mid-workflow exits. Keep one immediately before catch and one inside catch."
  }
} else {
  Write-Host "[OK] ScaleRecovery appears exactly once before catch and exactly once inside catch."
}

if ($dataLoaderMissing) {
  $failed = $true
  Write-Host "[FAIL] Missing DataLoader script."
} else {
  Write-Host "[OK] DataLoader script is present."
}

if ($loaderLegacyHits.Count -gt 0) {
  $failed = $true
  Write-Host "[FAIL] DataLoader still has legacy direct-login/platform scaffolding."
  $loaderLegacyHits | ForEach-Object { Write-Host $_ }
} else {
  Write-Host "[OK] DataLoader legacy scaffolding scan is clean."
}

if (-not $loaderDh2Commented) {
  $failed = $true
  Write-Host "[FAIL] DataLoader DH2 credential block is not commented as required."
} else {
  Write-Host "[OK] DataLoader DH2 credential block is commented."
}

if (-not $loaderFedaActive) {
  $failed = $true
  Write-Host "[FAIL] DataLoader FEDA credential block is not active."
} else {
  Write-Host "[OK] DataLoader FEDA credential block is active."
}

if ($loaderPerformanceHits.Count -lt 4) {
  $failed = $true
  Write-Host "[FAIL] DataLoader performance_data wiring looks incomplete."
} else {
  Write-Host "[OK] DataLoader performance_data wiring for sut/mill credentials is present."
}

if (-not $loaderIfElseGuardOk) {
  $failed = $true
  Write-Host "[FAIL] DataLoader If/Else control-flow guard is missing or incomplete."
  if ($verboseFailures) {
    Write-Host "  Hint: keep If (the number of keys in performance_data is 0) ... Else ... End If."
  }
} else {
  Write-Host "[OK] DataLoader If/Else control-flow guard is present."
}

if (-not $csvPresent) {
  $failed = $true
  Write-Host "[FAIL] Missing one or more required workflow CSV files."
  if ($verboseFailures) {
    Write-Host "  Hint: ensure both files exist: _LoginData.csv, _WorkflowData.csv."
  }
} else {
  Write-Host "[OK] Required workflow CSV files are present."
}

if ($csvPresent -and -not $csvShapeOk) {
  $failed = $true
  Write-Host "[FAIL] CSV row shape invalid. Expected one header row and one data row in each workflow CSV."
} elseif ($csvPresent) {
  Write-Host "[OK] Workflow CSV row shape is one header row + one data row."
}

if ($csvPresent -and -not $csvColumnsOk) {
  $failed = $true
  Write-Host "[FAIL] One or more workflow CSV files have header/value column-count mismatch."
} elseif ($csvPresent) {
  Write-Host "[OK] Workflow CSV column counts are consistent."
}

if ($csvPresent -and -not $loginHeaderOk) {
  $failed = $true
  Write-Host "[FAIL] LoginData CSV must include millUsername* and millPassword* headers."
} elseif ($csvPresent) {
  Write-Host "[OK] LoginData CSV includes millUsername*/millPassword* headers."
}

if ($csvPresent -and -not $workflowHeaderOk) {
  $failed = $true
  Write-Host "[FAIL] WorkflowData CSV has no headers."
} elseif ($csvPresent) {
  Write-Host "[OK] WorkflowData CSV has headers."
}

if ($failed) {
  Write-Host ""
  Write-Host "Validation result: FAIL"
  exit 1
}

Write-Host ""
Write-Host "Validation result: PASS"
exit 0
