param(
    [string]$PackageRoot = (Split-Path $PSScriptRoot -Parent),
    [string]$ReportPath = ''
)
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath($PackageRoot).TrimEnd('\')
$outer=Split-Path $root -Parent
$issues=New-Object 'System.Collections.Generic.List[object]'
function CheckManifest([string]$Base,[string]$Manifest,[string]$Identity) {
    if(!(Test-Path -LiteralPath $Manifest -PathType Leaf)){throw 'Missing manifest'}
    $expected=([IO.File]::ReadAllText($Identity)).Trim().Split(' ')[0]
    if((Get-FileHash -LiteralPath $Manifest -Algorithm SHA256).Hash -ne $expected){throw 'Manifest identity mismatch'}
    $rows=@(Import-Csv -LiteralPath $Manifest -Encoding UTF8)
    if(!$rows.Count){throw 'Empty manifest'}
    $seen=@{}
    foreach($row in $rows){
        if([IO.Path]::IsPathRooted($row.Path)){throw 'Absolute manifest path'}
        $path=[IO.Path]::GetFullPath((Join-Path $Base $row.Path))
        if(!$path.StartsWith($Base+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe manifest path'}
        if($seen.ContainsKey($row.Path)){throw 'Duplicate manifest path'}
        $seen[$row.Path]=$true
        if(!(Test-Path -LiteralPath $path -PathType Leaf)){$issues.Add([pscustomobject]@{Path=$row.Path;Issue='missing'});continue}
        if((Get-Item -LiteralPath $path).Length -ne [long]$row.Bytes){$issues.Add([pscustomobject]@{Path=$row.Path;Issue='size'});continue}
        if((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $row.SHA256){$issues.Add([pscustomobject]@{Path=$row.Path;Issue='sha256'})}
    }
    return $rows
}
$rows=@(CheckManifest $root (Join-Path $root 'manifests/package_files.csv') (Join-Path $root 'manifests/package_files.sha256'))
$complete=Test-Path -LiteralPath (Join-Path $root 'manifests/delivery_files.csv')
$wholeChecked=$false
if($complete -and (Test-Path -LiteralPath (Join-Path $outer '完整界面设计说明书.docx'))){
    $all=@(CheckManifest $outer (Join-Path $root 'manifests/delivery_files.csv') (Join-Path $root 'manifests/delivery_files.sha256'))
    $wholeChecked=$true
    $known=@{}
    foreach($row in $all){$known[$row.Path]=$true}
    foreach($file in Get-ChildItem -LiteralPath $outer -Recurse -File){
        $relative=$file.FullName.Substring($outer.Length+1).Replace('\','/')
        if(!$known.ContainsKey($relative) -and $file.Name -notin @('delivery_files.csv','delivery_files.sha256')){
            $issues.Add([pscustomobject]@{Path=$relative;Issue='unexpected'})
        }
    }
}
$result=[ordered]@{Version='R06';Root=$root;ProgramPayloadCount=$rows.Count;CompleteDeliveryChecked=$wholeChecked;IssueCount=$issues.Count;Issues=@($issues.ToArray());Status=$(if($issues.Count -eq 0){'PASS_STATIC_INTEGRITY_ONLY'}else{'FAIL'});MatlabExecuted=$false;RuntimeValidated=$false}
$json=$result|ConvertTo-Json -Depth 6
if($ReportPath){
    $report=[IO.Path]::GetFullPath($ReportPath)
    if($report.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase) -or ($wholeChecked -and $report.StartsWith($outer+'\',[StringComparison]::OrdinalIgnoreCase))){throw 'Report must be outside immutable delivery'}
    if(Test-Path -LiteralPath $report){throw 'Do not overwrite report'}
    [IO.File]::WriteAllText($report,$json,(New-Object Text.UTF8Encoding($false)))
}
$json
if($issues.Count){exit 1}
