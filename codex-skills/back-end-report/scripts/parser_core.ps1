Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

function Read-BoundedArtifactCsvHeader([string]$Text, [int]$MaxChars = 2048) {
    $reader = [IO.StringReader]::new($Text)
    $header = New-Object Text.StringBuilder
    $quoted = $false
    try {
        for ($i = 0; $i -lt $MaxChars; $i++) {
            $value = $reader.Read()
            if ($value -lt 0) { return $header.ToString() }
            $char = [char]$value
            if ($char -eq '"') {
                [void]$header.Append($char)
                if ($quoted -and $reader.Peek() -eq [int][char]'"') {
                    if ($i + 1 -ge $MaxChars) { return $null }
                    [void]$header.Append([char]$reader.Read())
                    $i++
                    continue
                }
                $quoted = -not $quoted
                continue
            }
            if (!$quoted -and ($char -eq "`r" -or $char -eq "`n")) { return $header.ToString() }
            [void]$header.Append($char)
        }
        return $null
    } finally { $reader.Dispose() }
}

function Test-ArtifactServerMemoryCsvSchema([string]$Text) {
    try {
        $header = Read-BoundedArtifactCsvHeader $Text
        if ([string]::IsNullOrWhiteSpace($header)) { return $false }
        $rows = @(("$header`nx") | ConvertFrom-Csv)
        if (!$rows.Count) { return $false }
        $columns = @($rows[0].PSObject.Properties.Name | ForEach-Object { $_.ToLowerInvariant() })
        return (($columns -contains 'server_id') -and (($columns -contains 'rss_mb') -or ($columns -contains 'rss')))
    } catch { return $false }
}

function Get-ArtifactContentPolicy([IO.FileInfo]$File) {
    $textExtensions = @('.txt','.log','.csv','.tsv','.out','.xml','.json','.yaml','.yml','.conf','.cfg','.ini','.properties','.dat','.lst','.stat')
    $evidenceOnlyTextExtensions = @('.html','.htm','.js','.css','.sql','.ksh','.ksh_at','.sh','.prg','.ccl','.success')
    $evidenceNamePattern = '(cmb[_-]\d+|ndump|core[_-]?dump|diagnostic[_-]?dump|awr|workload[_-]?repository|sqlstat|sqlstats|sqlreport|sqlsummary|top[_-]?sql|db[_-]?(summary|report|health)|database[_-]?(summary|report)|regdump|registry|config|smaps|(^|[_\.-])gc([_\.-]|$)|gclog|meminfo|node[_-]?memory|rss|process|pid|server[_-]?memory)'
    $extension = $File.Extension.ToLowerInvariant()
    $skipContent = -not ([string]::IsNullOrEmpty($extension) -or $textExtensions -contains $extension -or (($evidenceOnlyTextExtensions -contains $extension) -and $File.Name -match $evidenceNamePattern))
    if ($skipContent) { return [pscustomobject]@{ read_content = $false; text = ''; read_error = $false } }
    try {
        if ($File.Length -gt 64MB) { return [pscustomobject]@{ read_content = $true; text = ''; read_error = $true } }
        [pscustomobject]@{ read_content = $true; text = [IO.File]::ReadAllText($File.FullName); read_error = $false }
    } catch {
        [pscustomobject]@{ read_content = $true; text = ''; read_error = $true }
    }
}

function Get-ArtifactCategory([IO.FileInfo]$File, [string]$Text) {
    $name = $File.Name.ToLowerInvariant(); $content = ([string]$Text).ToLowerInvariant()
    if ($name -match '(^|[_\.-])cmb[_-]\d+') { 'cmb' }
    elseif ($name -match 'ndump|core[_-]?dump|diagnostic[_-]?dump' -or $content -match 'ora-00600|ora-07445|exception stack') { 'ndump' }
    elseif ($name -match 'awr|workload[_-]?repository' -or $content -match 'snapshot begin.*duration') { 'awr' }
    elseif ($name -match 'sql(stat|stats|report|summary)|top[_-]?sql' -or $content -match 'sql_id.*plan_hash') { 'sql' }
    elseif ($name -match 'db[_-]?(summary|report|health)|database[_-]?(summary|report)' -or $content -match 'db_time|db time') { 'database' }
    elseif ($name -match 'regdump|registry|config' -or $content -match 'jvmargs|\-xms\d|\-xmx\d') { 'configuration' }
    elseif ($name -match 'smaps' -or $content -match 'private_dirty:\s*\d+') { 'smaps' }
    elseif ($name -match '(^|[_\.-])gc([_\.-]|$)|gclog' -or $content -match 'full gc|gc\(\d+\)') { 'gc' }
    elseif ($content -match 'memavailable:\s*\d+' -or $name -match 'meminfo|node[_-]?memory') { 'node-memory' }
    elseif (Test-ArtifactServerMemoryCsvSchema $Text) { 'server-memory' }
    elseif ($File.Extension -eq '.zip') { 'archive' }
    else { 'unknown' }
}

function ConvertFrom-ArtifactMatch($Match, [int]$Group = 1) {
    if ($Match.Success) { [double]::Parse($Match.Groups[$Group].Value, [Globalization.CultureInfo]::InvariantCulture) } else { $null }
}
function ConvertTo-ArtifactMB($Value, $Unit) {
    if ($null -eq $Value) { return $null }
    switch ($Unit.ToUpperInvariant()) { 'K' {[double]$Value/1024} 'M' {[double]$Value} 'G' {[double]$Value*1024} default {[double]$Value} }
}
function Add-ArtifactRecord($List, [string]$Kind, [string]$Node, [string]$Key, [hashtable]$Values, [string]$Source, [string]$Confidence = 'medium') {
    $List.Add([pscustomobject]@{kind=$Kind;node=$Node;key=$Key;values=[pscustomobject]$Values;source=$Source;confidence=$Confidence})
}

function Invoke-ArtifactParse([IO.FileInfo]$File, [string]$RelativePath, [string]$Node, [string]$RunName, [string]$Sha256) {
    $inventory = New-Object Collections.Generic.List[object]; $records = New-Object Collections.Generic.List[object]
    $zipEntries = New-Object Collections.Generic.List[object]; $errors = New-Object Collections.Generic.List[object]
    $policy = Get-ArtifactContentPolicy $File; $text = $policy.text
    if ($policy.read_error) {$errors.Add([pscustomobject]@{run=$RunName;node=$Node;category='parser';server_database=$null;timestamp=$File.LastWriteTimeUtc.ToString('o');severity='Warning';signature_message='Unreadable or oversized text artifact; content parsing skipped';count=1;source=$RelativePath})}
    $category = Get-ArtifactCategory $File $text
    $inventory.Add([pscustomobject]@{relative_path=$RelativePath;node=$Node;category=$category;length=[long]$File.Length;last_write_utc=$File.LastWriteTimeUtc.ToString('o');sha256=$Sha256;is_duplicate=$false;duplicate_of=$null})
    if ($File.Extension -eq '.zip') {
        try {$zip=[IO.Compression.ZipFile]::OpenRead($File.FullName);try{if($zip.Entries.Count-gt10000){throw 'ZIP entry count limit exceeded'};$total=0L;foreach($entry in $zip.Entries){$total+=$entry.Length;if($entry.Length-gt100MB-or$total-gt1GB){throw 'ZIP uncompressed size limit exceeded'};$entryPath=$entry.FullName.Replace('\','/');$unsafe=($entryPath-match'(^|/)\.\.(/|$)'-or$entryPath.StartsWith('/')-or$entryPath-match'^[A-Za-z]:');if($unsafe){$errors.Add([pscustomobject]@{run=$RunName;node=$Node;category='archive';server_database=$null;timestamp=$null;severity='Error';signature_message="ZIP traversal entry rejected: $entryPath";count=1;source=$RelativePath})}else{$zipEntries.Add([pscustomobject]@{source=$RelativePath;entry_path=$entryPath;length=[long]$entry.Length})}}}finally{$zip.Dispose()}}catch{$errors.Add([pscustomobject]@{run=$RunName;node=$Node;category='archive';server_database=$null;timestamp=$null;severity='Error';signature_message="ZIP inspection failed: $($_.Exception.Message)";count=1;source=$RelativePath})}
    }
    switch ($category) {
      'node-memory' {$total=ConvertFrom-ArtifactMatch([regex]::Match($text,'(?im)^MemTotal:\s*(\d+)'));$available=ConvertFrom-ArtifactMatch([regex]::Match($text,'(?im)^MemAvailable:\s*(\d+)'));if($null-ne$total){$total=$total/1024};if($null-ne$available){$available=$available/1024};Add-ArtifactRecord $records node-memory $Node $Node @{total_mb=$total;available_mb=$available;used_mb=if($null-ne$total-and$null-ne$available){$total-$available}else{$null}} $RelativePath high}
      'server-memory' {foreach($row in @($text|ConvertFrom-Csv)){if($row.server_id){$serverId=$row.server_id.ToUpperInvariant();$rssValue=if(-not[string]::IsNullOrWhiteSpace([string]$row.rss_mb)){$row.rss_mb}else{$row.rss};Add-ArtifactRecord $records server-memory $Node "$Node|$serverId" @{server_id=$serverId;pid=$row.pid;rss_mb=if(-not[string]::IsNullOrWhiteSpace([string]$rssValue)){[double]::Parse([string]$rssValue,[Globalization.CultureInfo]::InvariantCulture)}else{$null};private_mb=if($row.private_mb){[double]$row.private_mb}else{$null}} $RelativePath high}}}
      'smaps' {$serverId=if($File.Name-match'(?i)(?:scp|scps|server)[_-]?(\d+)'){$matches[1]}else{$null};$pssMatches=@([regex]::Matches($text,'(?im)^Pss:\s*(\d+)'));$dirtyMatches=@([regex]::Matches($text,'(?im)^Private_Dirty:\s*(\d+)'));$pss=if($pssMatches.Count){($pssMatches|ForEach-Object{[double]$_.Groups[1].Value}|Measure-Object -Sum).Sum}else{$null};$privateDirty=if($dirtyMatches.Count){($dirtyMatches|ForEach-Object{[double]$_.Groups[1].Value}|Measure-Object -Sum).Sum}else{$null};Add-ArtifactRecord $records smaps $Node "$Node|$serverId" @{server_id=$serverId;pss_mb=if($null-ne$pss){$pss/1024}else{$null};private_dirty_mb=if($null-ne$privateDirty){$privateDirty/1024}else{$null}} $RelativePath medium}
      'gc' {$serverId=if($File.Name-match'(?i)(?:scp|server)[_-]?(\d+)'){$matches[1]}else{$null};foreach($match in [regex]::Matches($text,'(?i)(\d+(?:\.\d+)?)([KMG])->(\d+(?:\.\d+)?)([KMG]).*?(?:(\d+(?:\.\d+)?)\s*(ms|secs?|s))')){$pause=[double]$match.Groups[5].Value;if($match.Groups[6].Value-notmatch'^ms$'){$pause*=1000};Add-ArtifactRecord $records gc $Node "$Node|$serverId" @{server_id=$serverId;before_gc_mb=ConvertTo-ArtifactMB $match.Groups[1].Value $match.Groups[2].Value;after_gc_mb=ConvertTo-ArtifactMB $match.Groups[3].Value $match.Groups[4].Value;pause_ms=$pause} $RelativePath medium}}
      'configuration' {foreach($line in($text-split'\r?\n')){if($line-match'(?i)(?:SCP)?(\d+)\.jvmargs\s*=\s*(.*)'){$serverId=$matches[1];$arguments=$matches[2];$xmsMatch=[regex]::Match($arguments,'(?i)-Xms(\d+)([KMG])');$xmxMatch=[regex]::Match($arguments,'(?i)-Xmx(\d+)([KMG])');$xms=ConvertFrom-ArtifactMatch $xmsMatch;$xmx=ConvertFrom-ArtifactMatch $xmxMatch;Add-ArtifactRecord $records config $Node "$Node|$serverId" @{server_id=$serverId;xms_mb=if($xms){ConvertTo-ArtifactMB $xms $xmsMatch.Groups[2].Value}else{$null};xmx_mb=if($xmx){ConvertTo-ArtifactMB $xmx $xmxMatch.Groups[2].Value}else{$null};collector=if($arguments-match'Use([A-Za-z0-9]+)GC'){$matches[1]}else{$null};gc_logging=[bool]($arguments-match'(?i)loggc|Xlog:gc');jvmargs=$arguments} $RelativePath high}elseif($line-match'(?i)(?:SCP)?(\d+)\.instances\s*=\s*(\d+)'){Add-ArtifactRecord $records instances $Node "$Node|$($matches[1])" @{server_id=$matches[1];configured_instances=[double]$matches[2]} $RelativePath high}}}
      'database' {$database=if($text-match'(?i)database[=:]\s*([\w$#]+)'){$matches[1].ToUpper()}else{$null};$instance=if($text-match'(?i)instance[=:]\s*([\w$#]+)'){$matches[1].ToUpper()}else{$null};foreach($specification in @(@('SGA_MB','SGA MB','MB'),@('PGA_MB','PGA MB','MB'),@('DB_TIME_S','DB Time','seconds'),@('DB_CPU_S','DB CPU','seconds'))){$match=[regex]::Match($text,"(?i)$($specification[0])[=:]\s*(\d+(?:\.\d+)?)");if($match.Success){Add-ArtifactRecord $records database $Node "$database|$instance|$($specification[1])" @{database=$database;instance=$instance;metric=$specification[1];value=(ConvertFrom-ArtifactMatch $match);unit=$specification[2]} $RelativePath medium}}}
      'sql' {foreach($row in @($text|ConvertFrom-Csv)){if($row.sql_id){$database=if($row.database){$row.database.ToUpper()}else{$null};Add-ArtifactRecord $records sql $Node "$database|$($row.sql_id.ToLower())" @{database=$database;sql_id=$row.sql_id.ToLower();plan_hash=if($row.plan_hash){[double]$row.plan_hash}else{$null};module_schema=$null;executions=if($row.executions){[double]$row.executions}else{$null};elapsed_ms=if($row.elapsed_ms){[double]$row.elapsed_ms}else{$null};cpu_ms=if($row.cpu_ms){[double]$row.cpu_ms}else{$null};buffer_gets=if($row.buffer_gets){[double]$row.buffer_gets}else{$null};disk_reads=if($row.disk_reads){[double]$row.disk_reads}else{$null};rows=if($row.rows){[double]$row.rows}else{$null}} $RelativePath high}}}
      'awr' {$database=if($text-match'(?i)Database:\s*([\w$#]+)'){$matches[1].ToUpper()}else{$null};$instance=if($text-match'(?i)Instance:\s*([\w$#]+)'){$matches[1].ToUpper()}else{$null};$duration=ConvertFrom-ArtifactMatch([regex]::Match($text,'(?i)Duration:\s*(\d+(?:\.\d+)?)\s*minutes'));$workload=ConvertFrom-ArtifactMatch([regex]::Match($text,'(?im)^Executions:\s*(\d+(?:\.\d+)?)'));$period=if($text-match'(?i)Snapshot Begin:\s*(\d+)\s*End:\s*(\d+)'){"$($matches[1])-$($matches[2])"}else{$null};foreach($specification in @(@('DB Time','DB Time:\s*(\d+(?:\.\d+)?)','seconds'),@('DB CPU','DB CPU:\s*(\d+(?:\.\d+)?)','seconds'))){$value=ConvertFrom-ArtifactMatch([regex]::Match($text,$specification[1],[Text.RegularExpressions.RegexOptions]::IgnoreCase));if($null-ne$value){Add-ArtifactRecord $records awr $Node "$database|$instance|$($specification[0])" @{database=$database;instance=$instance;metric=$specification[0];value=$value;unit=$specification[2];duration_minutes=$duration;workload=$workload;period=$period} $RelativePath medium}}}
      'ndump' {$serverId=if($File.Name-match'(?i)(?:SCP)?(\d+)'){$matches[1]}else{$null};$signature=if($text-match'(?im)(ORA-\d+[^\r\n]*)'){$matches[1]}else{$null};Add-ArtifactRecord $records ndump $Node "$Node|$serverId" @{server_instance=$serverId;size_mb=$File.Length/1MB;timestamp=$File.LastWriteTimeUtc.ToString('o');signature=$signature} $RelativePath medium;if($signature){$errors.Add([pscustomobject]@{run=$RunName;node=$Node;category='ndump';server_database=$serverId;timestamp=$File.LastWriteTimeUtc.ToString('o');severity='Error';signature_message=$signature;count=1;source=$RelativePath})}}
      'cmb' {$serverId=if($File.Name-match'(?i)cmb[_-](?:scp)?(\d+)'){$matches[1]}else{$null};$signatures=@([regex]::Matches($text,'(?im)^.*\b(?:WARN(?:ING)?|ERROR|FATAL)\b.*$')|ForEach-Object{$_.Value.Trim()});Add-ArtifactRecord $records cmb $Node "$Node|$serverId" @{server_id=$serverId;size_mb=$File.Length/1MB;timestamp=$File.LastWriteTimeUtc.ToString('o');warnings_errors=$signatures.Count;signatures=$signatures} $RelativePath high;foreach($signature in $signatures){$errors.Add([pscustomobject]@{run=$RunName;node=$Node;category='cmb';server_database=$serverId;timestamp=$File.LastWriteTimeUtc.ToString('o');severity=if($signature-match'(?i)ERROR|FATAL'){'Error'}else{'Warning'};signature_message=$signature;count=1;source=$RelativePath})}}
    }
    [pscustomobject]@{inventory=$inventory.ToArray();records=$records.ToArray();zip_entries=$zipEntries.ToArray();errors=$errors.ToArray()}
}
