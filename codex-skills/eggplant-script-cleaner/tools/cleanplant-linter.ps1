param(
  [Parameter(Mandatory = $true)]
  [string[]]$Path,
  [switch]$Write,
  [switch]$Check,
  [int]$IndentWidth = 1,
  [ValidateSet("Tabs","Spaces")]
  [string]$IndentStyle = "Tabs"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-Indent {
  param(
    [int]$Level,
    [int]$Width,
    [string]$Style
  )
  if ($Level -le 0) { return "" }
  if ($Style -eq "Spaces") {
    return (" " * ($Level * $Width))
  }
  return ("`t" * $Level)
}

function Is-CommentOnly {
  param([string]$Trimmed)
  if ($Trimmed -eq "") { return $false }
  return (
    $Trimmed.StartsWith("//") -or
    $Trimmed.StartsWith("#") -or
    $Trimmed.StartsWith("--")
  )
}

function Is-Opener {
  param([string]$Trimmed)
  if ($Trimmed -eq "") { return $false }
  if (Is-CommentOnly -Trimmed $Trimmed) { return $false }

  if ($Trimmed -match '(?i)\.\s*wfTestCase\b') { return $true }
  if ($Trimmed -match '(?i)^if\b') {
    # Block IF opener:
    # - lines without THEN (SenseTalk style block form)
    # - lines ending in THEN with no trailing executable statement
    if ($Trimmed -notmatch '(?i)\bthen\b') { return $true }
    if ($Trimmed -match '(?i)\bthen\s*$') { return $true }
    return $false
  }
  if ($Trimmed -match '(?i)^repeat\b') { return $true }
  if ($Trimmed -match '(?i)^try\b') { return $true }
  if ($Trimmed -match '(?i)^switch\b') { return $true }
  return $false
}

function Is-Mid {
  param([string]$Trimmed)
  if ($Trimmed -eq "") { return $false }
  if (Is-CommentOnly -Trimmed $Trimmed) { return $false }
  return (
    $Trimmed -match '(?i)^else(\b|$)' -or
    $Trimmed -match '(?i)^catch\b'
  )
}

function Is-Closer {
  param([string]$Trimmed)
  if ($Trimmed -eq "") { return $false }
  if (Is-CommentOnly -Trimmed $Trimmed) { return $false }
  return (
    $Trimmed -match '(?i)^end if\b' -or
    $Trimmed -match '(?i)^end repeat\b' -or
    $Trimmed -match '(?i)^end try\b' -or
    $Trimmed -match '(?i)^end switch\b' -or
    $Trimmed -match '(?i)^EndTestCase\b'
  )
}

function Format-Content {
  param(
    [string[]]$Lines,
    [int]$Width,
    [string]$Style
  )

  $indent = 0
  $formatted = New-Object System.Collections.Generic.List[string]

  foreach ($line in $Lines) {
    $trimmed = $line.Trim()

    if ($trimmed -eq "") {
      $formatted.Add("")
      continue
    }

    $isCloser = Is-Closer -Trimmed $trimmed
    $isMid = Is-Mid -Trimmed $trimmed

    if ($isCloser -or $isMid) {
      $indent = [Math]::Max(0, $indent - 1)
    }

    $formatted.Add((Get-Indent -Level $indent -Width $Width -Style $Style) + $trimmed)

    if ($isMid) {
      $indent++
      continue
    }

    if (Is-Opener -Trimmed $trimmed) {
      $indent++
    }
  }

  return ,$formatted
}

$hasStructureErrors = $false

function Test-IfStructure {
  param(
    [string[]]$Lines,
    [string]$FilePath
  )

  $ifStack = New-Object System.Collections.Generic.Stack[int]
  $issues = New-Object System.Collections.Generic.List[string]

  for ($idx = 0; $idx -lt $Lines.Count; $idx++) {
    $lineNo = $idx + 1
    $trimmed = $Lines[$idx].Trim()
    if ($trimmed -eq "") { continue }
    if (Is-CommentOnly -Trimmed $trimmed) { continue }

    $isEndIf = ($trimmed -match '(?i)^end if\b')
    if ($isEndIf) {
      if ($ifStack.Count -eq 0) {
        $issues.Add(("line {0}: End If without matching block If" -f $lineNo))
      } else {
        [void]$ifStack.Pop()
      }
      continue
    }

    # Block IF opener only:
    # - starts with If
    # - either no THEN or THEN with no trailing statement
    $isIf = ($trimmed -match '(?i)^if\b')
    if ($isIf) {
      $hasThen = ($trimmed -match '(?i)\bthen\b')
      $blockIf = (-not $hasThen) -or ($trimmed -match '(?i)\bthen\s*$')
      if ($blockIf) {
        $ifStack.Push($lineNo)
      }
    }
  }

  while ($ifStack.Count -gt 0) {
    $openLine = $ifStack.Pop()
    $issues.Add(("line {0}: block If missing End If" -f $openLine))
  }

  if ($issues.Count -gt 0) {
    $script:hasStructureErrors = $true
    Write-Host ("[if-structure-fail] {0}" -f $FilePath)
    foreach ($m in $issues) {
      Write-Host ("  {0}" -f $m)
    }
  } else {
    Write-Host ("[if-structure-ok] {0}" -f $FilePath)
  }
}

$totalChanged = 0
$processed = 0

foreach ($p in $Path) {
  if (-not (Test-Path -LiteralPath $p)) {
    throw "Missing file: $p"
  }

  $full = (Resolve-Path -LiteralPath $p).Path
  $original = Get-Content -LiteralPath $full
  Test-IfStructure -Lines $original -FilePath $full
  $formatted = Format-Content -Lines $original -Width $IndentWidth -Style $IndentStyle

  $same = ($original.Count -eq $formatted.Count)
  if ($same) {
    for ($i = 0; $i -lt $original.Count; $i++) {
      if ($original[$i] -cne $formatted[$i]) { $same = $false; break }
    }
  }

  $processed++

  if (-not $same) {
    $totalChanged++
    if ($Write) {
      Set-Content -LiteralPath $full -Value $formatted
      Write-Host "[fixed] $full"
    } else {
      Write-Host "[needs-format] $full"
    }
  } else {
    Write-Host "[ok] $full"
  }
}

Write-Host ""
Write-Host ("Processed: {0}" -f $processed)
Write-Host ("Needs format: {0}" -f $totalChanged)

if ($hasStructureErrors) {
  exit 1
}

if ($Check -and $totalChanged -gt 0) {
  exit 1
}

exit 0
