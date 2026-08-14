[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Name,

    [string]$SourceRoot = '\\dh2ffs01\ablpub\ablscale3\ABLCAPUTIL',

    [string]$DestinationRoot = '\\cernerwhq1\india\ABL'
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem

function Get-CmbIdentifier {
    param([string]$RawName)

    $match = [regex]::Match($RawName, '(?i)(?:cmb[_-]?|scp[_-]?)?0*(\d{1,6})')
    if (-not $match.Success) {
        throw "Could not find an SCP/CMB number in '$RawName'. Examples: SCP2030, 2030, cmb_2030_*."
    }

    $number = [int]$match.Groups[1].Value
    $folderId = [string]$number
    if ($number -lt 1000) {
        $fileId = ('{0:D4}' -f $number)
    }
    else {
        $fileId = [string]$number
    }

    [pscustomobject]@{
        Number = $number
        FolderName = "SCP$folderId"
        FilePattern = "cmb_$fileId" + '_*'
    }
}

$id = Get-CmbIdentifier -RawName $Name
$destRoot = Join-Path $DestinationRoot $id.FolderName

$runs = @(
    @{ Release = '2026.2.01ST6'; RunName = '20260406_2026.2.01ST6_3000_R43_MidLevel'; Nodes = @('ABLSCALE3APP01', 'ABLSCALE3APP02') },
    @{ Release = '2026.2.01ST6'; RunName = '20260407_2026.2.01ST6_3000_R46_MidLevel'; Nodes = @('ABLSCALE3APP01', 'ABLSCALE3APP02') },
    @{ Release = '2026.3.01ST6'; RunName = '20260527_2026.3.01ST6_3000_R20_MidLevel'; Nodes = @('ABLSCALE3APP01', 'ABLSCALE3APP02') },
    @{ Release = '2026.3.01ST6'; RunName = '20260603_2026.3.01ST6_3000_R48_MidLevel'; Nodes = @('ABLSCALE3APP01', 'ABLSCALE3APP02') }
)

New-Item -ItemType Directory -Force -Path $destRoot | Out-Null
$results = New-Object System.Collections.Generic.List[object]

foreach ($run in $runs) {
    foreach ($node in $run.Nodes) {
        $nodeLower = $node.ToLowerInvariant()
        $zipPath = Join-Path (Join-Path (Join-Path $SourceRoot $run.Release) $run.RunName) (Join-Path $node "$nodeLower`_cmb_temp.zip")
        $destDir = Join-Path (Join-Path (Join-Path $destRoot $run.Release) $run.RunName) $node
        New-Item -ItemType Directory -Force -Path $destDir | Out-Null

        if (-not (Test-Path -LiteralPath $zipPath)) {
            $results.Add([pscustomobject]@{
                Release = $run.Release
                Run = $run.RunName
                Node = $node
                Status = 'ZIP_MISSING'
                Count = 0
                Destination = $destDir
            })
            continue
        }

        $zip = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
        try {
            $entries = @($zip.Entries | Where-Object {
                -not [string]::IsNullOrEmpty($_.Name) -and
                (($_.FullName -replace '\\', '/') -like 'cerner/d_ablscale3/temp/*') -and
                $_.Name -like $id.FilePattern
            })

            foreach ($entry in $entries) {
                $destFile = Join-Path $destDir $entry.Name
                [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $destFile, $true)
            }

            $results.Add([pscustomobject]@{
                Release = $run.Release
                Run = $run.RunName
                Node = $node
                Status = if ($entries.Count -gt 0) { 'COPIED' } else { 'NO_MATCH' }
                Count = $entries.Count
                Destination = $destDir
            })
        }
        finally {
            $zip.Dispose()
        }
    }
}

$results | Sort-Object Release, Run, Node | Format-Table -AutoSize
$total = ($results | Where-Object Status -eq 'COPIED' | Measure-Object -Property Count -Sum).Sum
if ($null -eq $total) {
    $total = 0
}

"NAME=$Name"
"PATTERN=$($id.FilePattern)"
"DEST=$destRoot"
"TOTAL_COPIED=$total"
