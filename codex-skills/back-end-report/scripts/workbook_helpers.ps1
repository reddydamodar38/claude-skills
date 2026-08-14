function Get-ObjectValue($Object,[string]$Name){if($null-eq$Object){return $null};$p=$Object.PSObject.Properties[$Name];if($p){$p.Value}else{$null}}
function Get-DisplayText($Value){if($null-eq$Value){''}elseif($Value-is[Array]){$Value-join'; '}else{[string]$Value}}
function Get-Severity($Assessment){$s=Get-ObjectValue $Assessment 'severity';if($s){[string]$s}elseif($Assessment-is[string]-and$Assessment-match'(?i)high|medium|low|none'){$matches[0]}else{'None'}}
function Format-Assessment($Assessment){
 if($null-eq$Assessment){return ''};if($Assessment-is[string]){return $Assessment}
 $severity=Get-Severity $Assessment;$confidence=Get-DisplayText (Get-ObjectValue $Assessment 'confidence');$evidence=Get-DisplayText (Get-ObjectValue $Assessment 'evidence')
 $cause=Get-DisplayText (Get-ObjectValue $Assessment 'likely_cause');$route=Get-DisplayText (Get-ObjectValue $Assessment 'route')
 "Severity: $severity | Confidence: $confidence | Evidence: $evidence | Cause: $cause | Route: $route"
}
function Resolve-ProvenancePath([string]$Source,[string]$BaselineRoot,[string]$CurrentRoot){
 if($Source-notmatch'^(baseline|current):(.+)$'){return $null};$root=if($matches[1]-eq'baseline'){$BaselineRoot}else{$CurrentRoot}
 if([string]::IsNullOrWhiteSpace($root)){return $null};$relative=$matches[2].TrimStart('/','\')
 $rootFull=[IO.Path]::GetFullPath($root).TrimEnd('\','/');$candidate=[IO.Path]::GetFullPath((Join-Path $rootFull $relative))
 if(!$candidate.StartsWith($rootFull+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){return $null}
 $item=Get-Item -LiteralPath $candidate -Force -ErrorAction SilentlyContinue;while($item-and$item.FullName.StartsWith($rootFull,[StringComparison]::OrdinalIgnoreCase)){if(($item.Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0){return $null};$item=$item.Parent}
 if(Test-Path -LiteralPath $candidate -PathType Leaf){$candidate}else{$null}
}
function Test-PlanChange($Row){
 $be=Get-ObjectValue $Row 'executions_baseline';$ce=Get-ObjectValue $Row 'executions_current'
 if(($null-eq$be)-ne($null-eq$ce)){return $true}
 $baseline=@(Get-ObjectValue $Row 'baseline_plan_hashes');$current=@(Get-ObjectValue $Row 'current_plan_hashes')
 $b=@($baseline|Where-Object{$null-ne$_}|ForEach-Object{"$_"}|Sort-Object -Unique);$c=@($current|Where-Object{$null-ne$_}|ForEach-Object{"$_"}|Sort-Object -Unique)
 $b.Count-gt0-and$c.Count-gt0-and(($b-join'|')-ne($c-join'|'))
}
function Test-CorrelatedConfig($Config,$Findings){
 $node=Get-DisplayText (Get-ObjectValue $Config 'node');$server=Get-DisplayText (Get-ObjectValue $Config 'server_id');if(!$server){$server=Get-DisplayText (Get-ObjectValue $Config 'server_instance_id')}
 if(!$node-or!$server){return $false}
 @($Findings|Where-Object{(Get-Severity (Get-ObjectValue $_ 'assessment'))-in@('Medium','High')-and(Get-DisplayText (Get-ObjectValue $_ 'node'))-eq$node-and((Get-DisplayText (Get-ObjectValue $_ 'server_id'))-eq$server-or(Get-DisplayText (Get-ObjectValue $_ 'server_instance_id'))-eq$server)}).Count-gt0
}
function Get-DeltaDisposition([string]$Metric,$Delta,$Assessment){
 if($null-eq$Delta){return'Unknown'};$parsed=0.0;if(![double]::TryParse("$Delta",[ref]$parsed)){return'Unknown'};if($parsed-eq0){return'Neutral'}
 $positiveIsGood=$Metric-match'(?i)available|free|throughput|success|hit.ratio'
 if(($parsed-gt0-and$positiveIsGood)-or($parsed-lt0-and!$positiveIsGood)){'Improvement'}else{'Regression'}
}
