[CmdletBinding(SupportsShouldProcess = $true)]
param(
  [Parameter(Mandatory = $true)]
  [string[]]$SourcePath,

  [Parameter(Mandatory = $true)]
  [string]$DestinationRoot,

  [string]$Pattern = 'cmb_0373_*'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.IO.Compression.FileSystem

function Test-ReadablePath {
  param([string]$LiteralPath)

  try {
    return [pscustomobject]@{
      Exists = [bool](Test-Path -LiteralPath $LiteralPath)
      Error = $null
    }
  } catch {
    return [pscustomobject]@{
      Exists = $false
      Error = $_.Exception.Message
    }
  }
}

function Get-AbutilSubproject {
  param(
    [string[]]$Parts,
    [int]$FallbackIndex
  )

  for ($i = 0; $i -lt $Parts.Count; $i++) {
    if ($Parts[$i] -ieq 'ABLCAPUTIL' -and ($i + 1) -lt $Parts.Count) {
      return $Parts[$i + 1]
    }
  }

  if ($FallbackIndex -ge 0 -and $FallbackIndex -lt $Parts.Count) {
    return $Parts[$FallbackIndex]
  }

  return 'unknown-subproject'
}

function Get-SourceParts {
  param([string]$Path)

  $normalized = $Path.TrimEnd('\')
  $parts = $normalized -split '\\'
  $zipIndex = -1

  for ($i = 0; $i -lt $parts.Count; $i++) {
    if ($parts[$i] -like '*.zip') {
      $zipIndex = $i
      break
    }
  }

  if ($zipIndex -ge 0) {
    $zipPath = ($parts[0..$zipIndex] -join '\')
    $internal = ''
    if ($zipIndex + 1 -lt $parts.Count) {
      $internal = ($parts[($zipIndex + 1)..($parts.Count - 1)] -join '/')
    }

    return [pscustomobject]@{
      SourceKind = 'Zip'
      ZipPath = $zipPath
      DirectoryPath = $null
      InternalPath = $internal.Trim('/')
      Subproject = Get-AbutilSubproject -Parts $parts -FallbackIndex ($zipIndex - 3)
      Run = if ($zipIndex -ge 2) { $parts[$zipIndex - 2] } else { 'unknown-run' }
      Node = if ($zipIndex -ge 1) { $parts[$zipIndex - 1] } else { 'unknown-node' }
    }
  }

  $ablcaputilIndex = -1
  for ($i = 0; $i -lt $parts.Count; $i++) {
    if ($parts[$i] -ieq 'ABLCAPUTIL') {
      $ablcaputilIndex = $i
      break
    }
  }

  $directorySubproject = Get-AbutilSubproject -Parts $parts -FallbackIndex ($parts.Count - 3)
  $directoryRun = if ($ablcaputilIndex -ge 0 -and ($ablcaputilIndex + 2) -lt $parts.Count) {
    $parts[$ablcaputilIndex + 2]
  } elseif ($parts.Count -ge 2) {
    $parts[$parts.Count - 2]
  } else {
    'unknown-run'
  }

  $directoryNode = if ($ablcaputilIndex -ge 0 -and ($ablcaputilIndex + 3) -lt $parts.Count) {
    $parts[$ablcaputilIndex + 3]
  } elseif ($parts.Count -ge 1) {
    $parts[$parts.Count - 1]
  } else {
    'unknown-node'
  }

  return [pscustomobject]@{
    SourceKind = 'Directory'
    ZipPath = $null
    DirectoryPath = $normalized
    InternalPath = $null
    Subproject = $directorySubproject
    Run = $directoryRun
    Node = $directoryNode
  }
}

function Copy-ZipMatches {
  param(
    [pscustomobject]$Source,
    [string]$Destination,
    [string]$NamePattern
  )

  $zipCheck = Test-ReadablePath -LiteralPath $Source.ZipPath
  if (-not $zipCheck.Exists) {
    return [pscustomobject]@{
      Subproject = $Source.Subproject
      Run = $Source.Run
      Node = $Source.Node
      Status = if ($zipCheck.Error) { 'InaccessibleZip' } else { 'MissingZip' }
      FilesCopied = 0
      Destination = $Destination
      Detail = if ($zipCheck.Error) { $zipCheck.Error } else { $Source.ZipPath }
    }
  }

  if ($PSCmdlet.ShouldProcess($Destination, "Create destination directory")) {
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
  }

  try {
    $zip = [System.IO.Compression.ZipFile]::OpenRead($Source.ZipPath)
  } catch {
    return [pscustomobject]@{
      Subproject = $Source.Subproject
      Run = $Source.Run
      Node = $Source.Node
      Status = 'ZipOpenFailed'
      FilesCopied = 0
      Destination = $Destination
      Detail = $_.Exception.Message
    }
  }

  try {
    $prefix = ''
    if ($Source.InternalPath) {
      $prefix = $Source.InternalPath.Replace('\', '/').Trim('/') + '/'
    }

    $matches = @($zip.Entries | Where-Object {
      $entryName = $_.FullName.Replace('\', '/')
      $inScope = if ($prefix) {
        $entryName.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)
      } else {
        $true
      }

      $inScope -and
        ([System.IO.Path]::GetFileName($entryName) -like $NamePattern) -and
        $_.FullName -notmatch '/$'
    })

    $copied = 0
    $fileNames = New-Object System.Collections.Generic.List[string]

    foreach ($entry in $matches) {
      $fileName = [System.IO.Path]::GetFileName($entry.FullName)
      if ([string]::IsNullOrWhiteSpace($fileName)) {
        continue
      }

      $outFile = Join-Path $Destination $fileName
      $fileNames.Add($fileName)

      if ($PSCmdlet.ShouldProcess($outFile, "Extract $($entry.FullName)")) {
        $entryStream = $entry.Open()
        try {
          $fileStream = [System.IO.File]::Open($outFile, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
          try {
            $entryStream.CopyTo($fileStream)
          } finally {
            $fileStream.Dispose()
          }
        } finally {
          $entryStream.Dispose()
        }
      }

      $copied++
    }

    return [pscustomobject]@{
      Subproject = $Source.Subproject
      Run = $Source.Run
      Node = $Source.Node
      Status = if ($matches.Count -gt 0) { 'OK' } else { 'NoMatches' }
      FilesCopied = $copied
      Destination = $Destination
      Detail = ($fileNames -join ', ')
    }
  } finally {
    $zip.Dispose()
  }
}

function Copy-DirectoryMatches {
  param(
    [pscustomobject]$Source,
    [string]$Destination,
    [string]$NamePattern
  )

  $directoryCheck = Test-ReadablePath -LiteralPath $Source.DirectoryPath
  if (-not $directoryCheck.Exists) {
    return [pscustomobject]@{
      Subproject = $Source.Subproject
      Run = $Source.Run
      Node = $Source.Node
      Status = if ($directoryCheck.Error) { 'InaccessibleDirectory' } else { 'MissingDirectory' }
      FilesCopied = 0
      Destination = $Destination
      Detail = if ($directoryCheck.Error) { $directoryCheck.Error } else { $Source.DirectoryPath }
    }
  }

  if ($PSCmdlet.ShouldProcess($Destination, "Create destination directory")) {
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
  }

  $matches = @(Get-ChildItem -LiteralPath $Source.DirectoryPath -Recurse -Force -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -like $NamePattern })

  $copied = 0
  $fileNames = New-Object System.Collections.Generic.List[string]

  foreach ($file in $matches) {
    $outFile = Join-Path $Destination $file.Name
    $fileNames.Add($file.Name)

    if ($PSCmdlet.ShouldProcess($outFile, "Copy $($file.FullName)")) {
      Copy-Item -LiteralPath $file.FullName -Destination $outFile -Force
    }

    $copied++
  }

  return [pscustomobject]@{
    Subproject = $Source.Subproject
    Run = $Source.Run
    Node = $Source.Node
    Status = if ($matches.Count -gt 0) { 'OK' } else { 'NoMatches' }
    FilesCopied = $copied
    Destination = $Destination
    Detail = ($fileNames -join ', ')
  }
}

if ($PSCmdlet.ShouldProcess($DestinationRoot, "Create destination root")) {
  New-Item -ItemType Directory -Path $DestinationRoot -Force | Out-Null
}

$summary = foreach ($path in $SourcePath) {
  $source = Get-SourceParts -Path $path
  $destination = Join-Path (Join-Path (Join-Path $DestinationRoot $source.Subproject) $source.Run) $source.Node

  if ($source.SourceKind -eq 'Zip') {
    Copy-ZipMatches -Source $source -Destination $destination -NamePattern $Pattern
  } else {
    Copy-DirectoryMatches -Source $source -Destination $destination -NamePattern $Pattern
  }
}

$summary | Sort-Object Subproject, Run, Node | Format-Table -AutoSize | Out-String -Width 4096
'TOTAL_FILES_COPIED=' + (($summary | Measure-Object -Property FilesCopied -Sum).Sum)
'DESTINATION_ROOT=' + $DestinationRoot
