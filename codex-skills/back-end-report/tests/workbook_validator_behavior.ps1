param()
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot;$validator=Join-Path $root 'scripts\validate_workbook.ps1';$template=Join-Path $root 'assets\reference-workbook.xlsx'
function Assert($x,[string]$m){if(!$x){throw "ASSERT: $m"}}
function Rename-Sheets([string]$path,[string[]]$names){
 Add-Type -AssemblyName System.IO.Compression;Add-Type -AssemblyName System.IO.Compression.FileSystem;$z=[IO.Compression.ZipFile]::Open($path,[IO.Compression.ZipArchiveMode]::Update)
 try{$e=$z.GetEntry('xl/workbook.xml');$r=[IO.StreamReader]::new($e.Open());try{[xml]$x=$r.ReadToEnd()}finally{$r.Dispose()};$nodes=@($x.SelectNodes("//*[local-name()='sheets']/*[local-name()='sheet']"));for($i=0;$i-lt$names.Count;$i++){$nodes[$i].name=$names[$i]};$content=$x.OuterXml;$e.Delete();$e=$z.CreateEntry('xl/workbook.xml');$w=[IO.StreamWriter]::new($e.Open());try{$w.Write($content)}finally{$w.Dispose()}}finally{$z.Dispose()}
}
$required=@('Read Me','Node Summary','Server Comparison','GC Comparison','Smaps End','Config Changes','Executive Summary','Database Summary','SQL Comparison','AWR Summary','Instance Summary','Ndump Summary','CMB Summary','Artifact Coverage','Errors & Warnings')
$bad=Join-Path ([IO.Path]::GetTempPath()) ("strict-headers-{0}.xlsx"-f[guid]::NewGuid());Copy-Item $template $bad
try{Rename-Sheets $bad $required;$caught='';try{&$validator -Path $bad -RequireExtended|Out-Null}catch{$caught=$_.Exception.Message};Assert ($caught-match'Header row|Exact headers') 'validator did not behaviorally reject invalid exact headers'}finally{Remove-Item $bad -Force -ErrorAction SilentlyContinue}
$bad=Join-Path ([IO.Path]::GetTempPath()) ("strict-order-{0}.xlsx"-f[guid]::NewGuid());Copy-Item $template $bad
try{$swapped=@($required);$swapped[6]='Database Summary';$swapped[7]='Executive Summary';Rename-Sheets $bad $swapped;$caught='';try{&$validator -Path $bad -RequireExtended|Out-Null}catch{$caught=$_.Exception.Message};Assert ($caught-match'Invalid sheet order') 'validator did not behaviorally reject exact sheet order'}finally{Remove-Item $bad -Force -ErrorAction SilentlyContinue}
Write-Output 'PASS: strict workbook validator behavior tests'

