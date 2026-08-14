param(
    [Parameter(Mandatory=$true)][string]$Path,
    [int]$MinimumCharts=0,
    [switch]$RequireExtended
)
$ErrorActionPreference='Stop'

$core=@('Read Me','Node Summary','Server Comparison','GC Comparison','Smaps End','Config Changes')
$extended=@('Executive Summary','Database Summary','SQL Comparison','AWR Summary','Instance Summary','Ndump Summary','CMB Summary','Artifact Coverage','Errors & Warnings')
$expectedHeaders=@{
 'Executive Summary'=@('Type','Category','Item','Assessment / Change / Route','Source','Count')
 'Database Summary'=@('Database','Instance','Node','Metric','Baseline','Current','Delta','Unit','Assessment','Source Paths')
 'SQL Comparison'=@('Database','SQL ID','Plan Hash','Module/Schema','Executions Baseline','Executions Current','Elapsed Baseline ms','Elapsed Current ms','Elapsed Delta %','CPU Baseline ms','CPU Current ms','Buffer Gets Baseline','Buffer Gets Current','Disk Reads Baseline','Disk Reads Current','Rows Baseline','Rows Current','Avg Elapsed Baseline ms','Avg Elapsed Current ms','Assessment','Source Paths')
 'AWR Summary'=@('Database','Instance','Baseline Period','Current Period','Metric/Wait Event','Baseline','Current','Delta','Unit','Assessment','Source Paths')
 'Instance Summary'=@('Node','Server/Instance ID','Name','Baseline Configured','Current Configured','Baseline Observed','Current Observed','Delta Instances','Baseline Xms MB','Current Xms MB','Baseline Xmx MB','Current Xmx MB','Baseline Collector','Current Collector','Baseline GC Logging','Current GC Logging','Assessment','Source Paths')
 'Ndump Summary'=@('Node','Server/Instance','Baseline Count','Current Count','Delta Count','Baseline MB','Current MB','Delta MB','Latest Baseline','Latest Current','Signature/Error','Assessment','Source Paths')
 'CMB Summary'=@('Node','Server ID','Baseline Count','Current Count','Delta Count','Baseline MB','Current MB','Delta MB','Baseline Warnings/Errors','Current Warnings/Errors','Key Difference','Assessment','Source Paths')
 'Artifact Coverage'=@('Run','Node','Category','File Count','Total MB','Latest Timestamp','Status','Source Paths')
 'Errors & Warnings'=@('Run','Node','Category','Server/Database','Timestamp','Severity','Signature/Message','Count','Source')
}

$required=@($core)
if($RequireExtended){$required+=@($extended)}
$resolved=(Resolve-Path -LiteralPath $Path).Path
Add-Type -AssemblyName System.IO.Compression.FileSystem

function Read-ZipXml($Zip,[string]$Name){
    $entry=$Zip.GetEntry($Name)
    if(!$entry){throw "Invalid XLSX: $Name missing."}
    $reader=New-Object IO.StreamReader($entry.Open())
    try{[xml]$reader.ReadToEnd()}finally{$reader.Dispose()}
}
function Cell-Text($Cell,$Shared){
    if($null -eq $Cell){return ''}
    $type=[string]$Cell.t
    if($type -eq 'inlineStr'){return [string]$Cell.is.t}
    $value=[string]$Cell.v
    if($type -eq 's' -and $value -match '^\d+$' -and [int]$value -lt $Shared.Count){return [string]$Shared[[int]$value]}
    return $value
}

$zip=[IO.Compression.ZipFile]::OpenRead($resolved)
try{
    foreach($worksheetEntry in @($zip.Entries|Where-Object{$_.FullName -match '^xl/worksheets/sheet\d+\.xml$'})){
        $rawReader=New-Object IO.StreamReader($worksheetEntry.Open())
        try{$rawSheet=$rawReader.ReadToEnd()}finally{$rawReader.Dispose()}
        if($rawSheet -match 't=["'']e["'']' -or $rawSheet -match '#(REF|VALUE|DIV/0|NAME\?|N/A|NUM|NULL)!?'){throw "Workbook contains formula/error cells in $($worksheetEntry.FullName)."}
        if($rawSheet -match '(?is)<f[^>]*>.*?(HYPERLINK|DDE|\[[^<]+\]).*?</f>'){throw "Workbook contains an external or active formula in $($worksheetEntry.FullName)."}
    }
    $workbook=Read-ZipXml $zip 'xl/workbook.xml'
    $names=@($workbook.SelectNodes("//*[local-name()='sheets']/*[local-name()='sheet']")|ForEach-Object{[string]$_.name})
    $missing=@($required|Where-Object{$names -notcontains $_})
    if($missing.Count){throw "Missing sheets: $($missing -join ', ')"}
    for($i=0;$i -lt $required.Count;$i++){
        if($names[$i] -ne $required[$i]){throw "Invalid sheet order at position $($i+1): expected '$($required[$i])', found '$($names[$i])'."}
    }

    if($names.Count-gt$required.Count){$unexpected=@($names[$required.Count..($names.Count-1)]|Where-Object{$_-notmatch '^S\d+\s'});if($unexpected.Count){throw "Unexpected non-detail sheets: $($unexpected -join ', ')"}}
    $shared=@()
    $sharedEntry=$zip.GetEntry('xl/sharedStrings.xml')
    if($sharedEntry){
        $sharedXml=Read-ZipXml $zip 'xl/sharedStrings.xml'
        $shared=@($sharedXml.SelectNodes("//*[local-name()='si']")|ForEach-Object{($_.SelectNodes(".//*[local-name()='t']")|ForEach-Object{[string]$_.InnerText}) -join ''})
    }
    $rels=Read-ZipXml $zip 'xl/_rels/workbook.xml.rels'
    $relationshipById=@{}
    foreach($rel in $rels.SelectNodes("//*[local-name()='Relationship']")){$relationshipById[[string]$rel.Id]=[string]$rel.Target}
    $sheetXmlByName=@{}
    foreach($sheet in $workbook.SelectNodes("//*[local-name()='sheets']/*[local-name()='sheet']")){
        $rid=[string]$sheet.GetAttribute('id','http://schemas.openxmlformats.org/officeDocument/2006/relationships')
        $target=$relationshipById[$rid] -replace '^/',''
        if($target -notmatch '^xl/'){$target='xl/'+($target -replace '^\.\./','')}
        $sheetXmlByName[[string]$sheet.name]=@{Path=$target;Xml=(Read-ZipXml $zip $target)}
    }

    $spreadsheetErrors=@()
    foreach($pair in $sheetXmlByName.GetEnumerator()){
        foreach($cell in $pair.Value.Xml.SelectNodes("//*[local-name()='c']")){
            $formula=[string]$cell.f;$value=[string]$cell.v
            if([string]$cell.t -eq 'e' -or $formula -match '#(REF|VALUE|DIV/0|NAME\?|N/A|NUM|NULL)!?' -or $value -match '^#(REF|VALUE|DIV/0|NAME\?|N/A|NUM|NULL)!?$'){
                $spreadsheetErrors+="$($pair.Key)!$([string]$cell.r)"
            }
        }
    }
    if($spreadsheetErrors.Count){throw "Workbook contains formula/error cells: $($spreadsheetErrors -join ', ')"}
        if($rawSheet -match '(?is)<f[^>]*>.*?(HYPERLINK|DDE|\[[^<]+\]).*?</f>'){throw "Workbook contains an external or active formula in $($worksheetEntry.FullName)."}

    $hyperlinkCount=0
    if($RequireExtended){
        $conditionalCount=0
        foreach($name in $extended){
            $item=$sheetXmlByName[$name];$xml=$item.Xml
            $headerRow=if($name -eq 'Executive Summary'){5}else{1}
            $firstRow=$xml.SelectSingleNode("//*[local-name()='sheetData']/*[local-name()='row'][@r='$headerRow']")
            if($null -eq $firstRow){throw "Header row $headerRow missing on '$name'."}
            $headers=@($firstRow.SelectNodes("./*[local-name()='c']")|ForEach-Object{Cell-Text $_ $shared})
            $expected=@($expectedHeaders[$name])
            if(($headers -join '|') -ne ($expected -join '|')){throw "Exact headers invalid on '$name'. Expected [$($expected -join ', ')]; found [$($headers -join ', ')]."}
            $unstyled=@($firstRow.SelectNodes("./*[local-name()='c']")|Where-Object{![string]$_.s -or [int]$_.s -eq 0})
            if($unstyled.Count){throw "Header style missing on '$name'."}
            $filter=$xml.SelectSingleNode("//*[local-name()='autoFilter']")
            if($null-eq$filter){throw "AutoFilter missing on '$name'."}
            $expectedFilterStart=if($name-eq'Executive Summary'){'A5:'}else{'A1:'}
            if([string]$filter.ref -notlike "$expectedFilterStart*"){throw "AutoFilter range invalid on '$name': $([string]$filter.ref)"}
            $pane=$xml.SelectSingleNode("//*[local-name()='pane' and @state='frozen']")
            $expectedSplit=if($name-eq'Executive Summary'){5}else{1}
            if($null -eq $pane -or [double]$pane.ySplit -ne $expectedSplit){throw "Frozen pane invalid on '$name'; expected $expectedSplit header rows."}
            $formatRanges=@($xml.SelectNodes("//*[local-name()='conditionalFormatting']")|ForEach-Object{[string]$_.sqref})
            $conditionalCount+=$formatRanges.Count
            foreach($deltaIndex in @(0..($expected.Count-1)|Where-Object{$expected[$_] -match '(?i)^delta|delta %'})){
                $letter='';$n=$deltaIndex+1
                while($n-gt0){$n--;$letter=[char](65+($n%26))+$letter;$n=[math]::Floor($n/26)}
                if(!@($formatRanges|Where-Object{$_ -match ('(^| )'+$letter+'2:')}).Count){throw "Conditional formatting missing for delta column '$($expected[$deltaIndex])' on '$name'."}
            }
            if($name-eq'SQL Comparison' -and !$formatRanges.Count){throw 'Plan-change conditional formatting missing on SQL Comparison.'}
            $links=@($xml.SelectNodes("//*[local-name()='hyperlink']"));$hyperlinkCount+=$links.Count
            if($links.Count){
                $sheetDirectory=[IO.Path]::GetDirectoryName($item.Path).Replace('\','/')
                $sheetFile=[IO.Path]::GetFileName($item.Path)
                $sheetRelsPath="$sheetDirectory/_rels/$sheetFile.rels"
                $sheetRels=Read-ZipXml $zip $sheetRelsPath;$sheetRelationshipById=@{}
                foreach($relationship in $sheetRels.SelectNodes("//*[local-name()='Relationship']")){$sheetRelationshipById[[string]$relationship.Id]=$relationship}
                foreach($link in $links){
                    $linkId=[string]$link.GetAttribute('id','http://schemas.openxmlformats.org/officeDocument/2006/relationships')
                    if(!$linkId){continue};$relationship=$sheetRelationshipById[$linkId]
                    if($null -eq $relationship){throw "Broken hyperlink relationship '$linkId' on '$name'."}
                    $target=[string]$relationship.Target
                    if($target -match '^(?i)https?://'){throw "Non-local hyperlink target on '$name': $target"}
                    $localTarget=$target
                    if($target -match '^(?i)file:'){try{$localTarget=([uri]$target).LocalPath}catch{throw "Invalid local hyperlink target on '$name': $target"}}
                    if(!(Test-Path -LiteralPath $localTarget)){throw "Local hyperlink target does not exist on '$name': $localTarget"}
                }
            }
        }
        if($hyperlinkCount -eq 0){
            $readMeXml=$sheetXmlByName['Read Me'].Xml
            $baselineRoot=Cell-Text ($readMeXml.SelectSingleNode("//*[local-name()='c'][@r='B7']")) $shared
            $currentRoot=Cell-Text ($readMeXml.SelectSingleNode("//*[local-name()='c'][@r='B8']")) $shared
            $resolvable=$false
            foreach($name in $extended){foreach($cell in $sheetXmlByName[$name].Xml.SelectNodes("//*[local-name()='c']")){foreach($source in @((Cell-Text $cell $shared) -split ';')){if($source.Trim() -match '^(baseline|current):(.+)$'){$root=if($matches[1]-eq'baseline'){$baselineRoot}else{$currentRoot};if($root-and(Test-Path -LiteralPath (Join-Path $root $matches[2].Trim()) -PathType Leaf)){$resolvable=$true}}}}}
            if($resolvable){throw 'Resolvable local source provenance exists but no workbook hyperlink was rendered.'}
        }
        if($conditionalCount -lt 3){throw "Expected conditional delta/plan-change formatting; found $conditionalCount conditional formatting ranges."}
        $styles=Read-ZipXml $zip 'xl/styles.xml'
        $wrapped=@($styles.SelectNodes("//*[local-name()='cellXfs']/*[local-name()='xf']/*[local-name()='alignment' and @wrapText='1']")).Count
        if($wrapped -lt 1){throw 'Expected a wrapped-text style for assessment/source columns.'}
        $numberFormats=@($styles.SelectNodes("//*[local-name()='cellXfs']/*[local-name()='xf'][number(@numFmtId) > 0]")).Count
        if($numberFormats -lt 1){throw 'Expected numeric/percentage cell formats.'}
        $xfs=@($styles.SelectNodes("//*[local-name()='cellXfs']/*[local-name()='xf']"))
        foreach($name in $extended|Where-Object{$_-ne'Executive Summary'}){
            $columns=@($sheetXmlByName[$name].Xml.SelectNodes("//*[local-name()='cols']/*[local-name()='col']"));$headers=@($expectedHeaders[$name])
            for($i=0;$i-lt$headers.Count;$i++){$columnNumber=$i+1;$column=@($columns|Where-Object{[int]$_.min-le$columnNumber-and[int]$_.max-ge$columnNumber}|Select-Object -Last 1);$styleId=if($column.Count){[int]$column[0].style}else{0};$xf=if($styleId-lt$xfs.Count){$xfs[$styleId]}else{$null}
                if($headers[$i]-match'(?i)%|baseline|current|delta|count|executions|reads|rows|mb|ms|instances'){if($null-eq$xf-or[int]$xf.numFmtId-eq0){throw "Numeric/percentage column format missing for '$($headers[$i])' on '$name'."}}
                if($headers[$i]-match'(?i)assessment|source|difference|signature|message'){if($null-eq$xf-or$null-eq$xf.alignment-or[string]$xf.alignment.wrapText-ne'1'){throw "Wrapped column format missing for '$($headers[$i])' on '$name'."}}
            }
        }
    }

    $charts=@($zip.Entries|Where-Object FullName -match '^xl/charts/chart\d+\.xml$').Count
    if($charts -lt $MinimumCharts){throw "Expected at least $MinimumCharts charts; found $charts."}
    Write-Output "PASS: $($names.Count) sheets, $charts charts, $hyperlinkCount hyperlinks; OPC workbook validation complete"
}finally{$zip.Dispose()}






