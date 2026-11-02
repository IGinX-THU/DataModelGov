param(
    [Parameter(Mandatory=$true)][string]$PackageRoot,
    [Parameter(Mandatory=$true)][string]$Destination,
    [Parameter(Mandatory=$true)][string]$ReceiptPath
)
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath($PackageRoot).TrimEnd('\')
$dest = [IO.Path]::GetFullPath($Destination).TrimEnd('\')
$receiptFull = [IO.Path]::GetFullPath($ReceiptPath)
if ($dest -eq $root -or $dest.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Destination must be outside the frozen package' }
foreach ($protected in @($root,$dest)) {
    if ($receiptFull -eq $protected -or $receiptFull.StartsWith($protected+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Receipt must be outside the package and working copy' }
}
if (-not (Test-Path -LiteralPath (Split-Path $receiptFull -Parent) -PathType Container)) { throw 'Receipt parent directory must already exist' }
if (Test-Path -LiteralPath $dest) { throw 'Destination must not already exist' }
if (Test-Path -LiteralPath $receiptFull) { throw 'Receipt already exists' }

function SafePath([string]$Base,[string]$Relative) {
    if ([IO.Path]::IsPathRooted($Relative)) { throw 'Absolute manifest path is forbidden' }
    $path = [IO.Path]::GetFullPath((Join-Path $Base $Relative))
    if (-not $path.StartsWith($Base+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe relative path' }
    return $path
}

# 先校验全部源文件，再创建工作目录；源包不完整时不留下貌似可运行的副本。
$manifest = Join-Path $root 'manifests/package_files.csv'
$expected = (Get-Content -LiteralPath (Join-Path $root 'manifests/package_files.sha256') -Raw).Trim().Split(' ')[0]
$actualManifest = (Get-FileHash -LiteralPath $manifest -Algorithm SHA256).Hash
if ($actualManifest -ne $expected) { throw 'Invalid manifest identity' }
$rows = @(Import-Csv -LiteralPath $manifest -Encoding UTF8)
if ($rows.Count -eq 0) { throw 'Empty package manifest' }
$seen = @{}
foreach ($row in $rows) {
    if ($seen.ContainsKey($row.Path)) { throw 'Duplicate package path' }
    $seen[$row.Path] = $row
    $source = SafePath $root $row.Path
    if ((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -ne $row.SHA256) { throw "Source identity mismatch: $($row.Path)" }
}

# 全模式运行视图仅取本包主模型的配套资产，不采用 advanced_C 中的其他副本或 AFO DLL。
# 这里只补目录布局，不改变发动机参数，也不是可重新编译的 C 工程。
$tune = 'programs/m_program_adaptive_tune/'
$runtimeRelative = 'programs/C_runtime'
$runtimeNames = @(
    'Turboshaft-TS.mdl', 'Turboshaft-TS-Split.mdl',
    'HPC02.MAP', 'HPC02_backup_before_surge_line_endpoint_20260706.MAP',
    'SingleStgRadialCompr.MAP', 'HPT02.MAP', 'LPT02.MAP', 'GTESS.dll'
)
foreach ($name in $runtimeNames) {
    if (-not $seen.ContainsKey($tune+$name)) { throw "Missing full-mode source in manifest: $name" }
}
New-Item -ItemType Directory -Path $dest | Out-Null
foreach ($row in $rows) {
    $target = SafePath $dest $row.Path
    New-Item -ItemType Directory -Path (Split-Path $target -Parent) -Force | Out-Null
    Copy-Item -LiteralPath (SafePath $root $row.Path) -Destination $target
    if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ne $row.SHA256) { throw "Copy identity mismatch: $($row.Path)" }
}
foreach ($name in 'package_files.csv','package_files.sha256') {
    Copy-Item -LiteralPath (Join-Path $root ('manifests/'+$name)) -Destination (Join-Path $dest ('manifests/'+$name))
}
$mapping = New-Object 'System.Collections.Generic.List[object]'
function MapExact([string]$SourceRelative,[string]$TargetRelative,[string]$Hash) {
    $source = SafePath $dest $SourceRelative
    $target = SafePath $dest $TargetRelative
    if ((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -ne $Hash) { throw "Wrong mapping source: $SourceRelative" }
    if (Test-Path -LiteralPath $target) {
        if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ne $Hash) { throw "Existing mapping conflicts: $TargetRelative" }
        $action = 'existing_identical'
    } else {
        New-Item -ItemType Directory -Path (Split-Path $target -Parent) -Force | Out-Null
        Copy-Item -LiteralPath $source -Destination $target
        $action = 'copied_exact_bytes'
    }
    if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ne $Hash) { throw 'Mapping verification failed' }
    $mapping.Add([pscustomobject]@{Source=$SourceRelative;Target=$TargetRelative;SHA256=$Hash;Action=$action})
}

# 保留原准备工具已经验证的 R018 历史来源和热资产映射，不扩大其运行身份。
foreach ($item in @(
    @('tc27_kurzke15_parameters.mat','13E094B4FBC2FAEC8042E8A073688AED91CE8CCC2C270B872F18E2EB56D8F0E8'),
    @('tc27_visser16_parameters.mat','C01AD1DDFEB5DC4447AD19A44EC4702D40792085D6E4EF59D9DFF719651A8719')
)) {
    $relative = 'MiddleData/three_component/tc27/R018_F3RNI/thermal_generated/'+$item[0]
    MapExact ('examples/TC27_source_R018/'+$relative) ($tune+$relative) $item[1]
}
$nested = Import-Csv -LiteralPath (Join-Path $dest 'examples/StartStop_public/assets/thermal_source/runtime_eight_files.csv') -Encoding UTF8
foreach ($item in $nested) {
    if ($item.Name -eq 'Turboshaft-TS.mdl') { $from='assets/candidate_model/'+$item.Name }
    elseif ($item.Name.EndsWith('.MAP')) { $from='assets/maps/'+$item.Name }
    else { $from='program/'+$item.Name }
    MapExact ('examples/StartStop_public/'+$from) ('examples/StartStop_public/assets/thermal_source/'+$item.SourcePath) $item.SHA256
}
foreach ($name in $runtimeNames) {
    $leaf = $name
    if ($name -eq 'GTESS.dll') { $leaf='x64/Release/GTESS.dll' }
    MapExact ($tune+$name) ($runtimeRelative+'/'+$leaf) $seen[$tune+$name].SHA256
}

# 写出相对路径合同。工作副本搬迁后根据新 deliveryRoot 拼接，绝对路径只供审计。
$layout = [ordered]@{
    schema='UI_WORK_COPY_LAYOUT_V2';revision='UI-R126';sourceManifestSHA256=$expected
    programRootRelative='programs/m_program_adaptive_tune';cRootRelative=$runtimeRelative
    dllRelative=($runtimeRelative+'/x64/Release/GTESS.dll');fullModeRuntimeFileCount=8
    requiresMatlab='R2019b';requiresNetwork=$false;CCompilationTested=$false
    note='Runtime assets only; all original payload bytes remain unchanged.'
}
$utf8 = New-Object Text.UTF8Encoding($false)
[IO.File]::WriteAllText((Join-Path $dest 'working_copy_layout.json'), ($layout|ConvertTo-Json -Depth 6), $utf8)
$receipt = [ordered]@{
    schema='UI_7P4_WORK_COPY_V2';revision='UI-R126';created=(Get-Date -Format o)
    source=$root;destination=$dest;sourceManifestSHA256=$expected;copiedPayload=$rows.Count
    mappings=@($mapping.ToArray());layout=$layout;sourceChanged=$false
    businessSourceChanged=$false;matlabExecuted=$false;workingCopyNotArchive=$true
}
[IO.File]::WriteAllText($receiptFull, ($receipt|ConvertTo-Json -Depth 7), $utf8)
$receipt|ConvertTo-Json -Depth 7
