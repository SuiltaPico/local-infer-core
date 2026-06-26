# Download Fluent UI, Tabler, and Font Awesome SVG icon sets into assets/svg/<namespace>/.
# PNG templates are generated with infer-core-helper (see -Rasterize).
param(
    [string]$OutDir = (Join-Path (Split-Path $PSScriptRoot -Parent) "assets"),
    [switch]$Rasterize,
    [int]$Size = 48,
    [ValidateSet("black", "white")]
    [string]$Color = "black",
    [int]$Jobs = 0,
    [string]$FluentVersion = "1.1.313",
    [string]$TablerVersion = "3.36.0",
    [string]$FaVersion = "6.7.2"
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "cargo_retry.ps1")
. (Join-Path $PSScriptRoot "icon_assets.ps1")

$RepoRoot = Split-Path $PSScriptRoot -Parent
$SvgRoot = Join-Path $OutDir "svg"
$IconsRoot = Join-Path $OutDir "icons"

function Ensure-NpmPackage {
    param(
        [string]$WorkDir,
        [string]$PackageSpec
    )
    New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
    Push-Location $WorkDir
    try {
        if (-not (Test-Path "package.json")) {
            npm init -y | Out-Null
        }
        npm install $PackageSpec --no-save --silent
    } finally {
        Pop-Location
    }
}

function Reset-Dir([string]$Path) {
    if (Test-Path $Path) {
        Remove-Item -Recurse -Force $Path
    }
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
}

function Copy-FlattenSvg {
    param(
        [string[]]$SourceFiles,
        [string]$DestDir,
        [scriptblock]$NameSelector,
        [switch]$Append
    )
    if (-not $Append) {
        Reset-Dir $DestDir
    } else {
        New-Item -ItemType Directory -Force -Path $DestDir | Out-Null
    }
    $seen = @{}
    if ($Append) {
        Get-ChildItem $DestDir -Filter *.svg -ErrorAction SilentlyContinue | ForEach-Object {
            $seen[$_.BaseName] = $true
        }
    }
    foreach ($src in $SourceFiles) {
        $name = & $NameSelector $src
        if (-not $name) { continue }
        if ($seen.ContainsKey($name)) { continue }
        $seen[$name] = $true
        Copy-Item -Force $src (Join-Path $DestDir "$name.svg")
    }
    return $seen.Count
}

function Invoke-RasterizeNamespace {
    param(
        [string]$CliBin,
        [string]$Namespace,
        [int]$Size,
        [string]$Color,
        [int]$Jobs
    )
    $svgDir = Join-Path $SvgRoot $Namespace
    $pngDir = Join-Path $IconsRoot $Namespace
    if (-not (Test-Path $svgDir)) {
        Write-Host "skip rasterize ($Namespace): missing $svgDir"
        return
    }
    $svgCount = (Get-ChildItem $svgDir -Filter *.svg -ErrorAction SilentlyContinue).Count
    if ($svgCount -eq 0) {
        Write-Host "skip rasterize ($Namespace): no svg files"
        return
    }

    Write-Host "rasterizing $Namespace ($svgCount svg -> $pngDir, ${Size}px, $Color) ..."
    Invoke-IconRasterizeSvg -CliBin $CliBin -SvgDir $svgDir -OutDir $pngDir -Size $Size -Color $Color -Jobs $Jobs
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
New-Item -ItemType Directory -Force -Path $SvgRoot | Out-Null
New-Item -ItemType Directory -Force -Path $IconsRoot | Out-Null

# Fluent UI System Icons (@fluentui/svg-icons) — canonical 24px regular outline set.
$FluentWork = Join-Path (Get-ScratchDir) "local-infer-core-fluent-$FluentVersion"
Write-Host "installing @fluentui/svg-icons@$FluentVersion ..."
Ensure-NpmPackage -WorkDir $FluentWork -PackageSpec "@fluentui/svg-icons@$FluentVersion"
$FluentSrc = Join-Path $FluentWork "node_modules\@fluentui\svg-icons\icons"
if (-not (Test-Path $FluentSrc)) {
    throw "Fluent SVG source not found: $FluentSrc"
}
$FluentFiles = Get-ChildItem -Path $FluentSrc -Recurse -Filter "*_24_regular.svg" | ForEach-Object { $_.FullName }
$FluentDest = Join-Path $SvgRoot "fluent"
$FluentCount = Copy-FlattenSvg -SourceFiles $FluentFiles -DestDir $FluentDest -NameSelector {
    param($Path)
    $base = [System.IO.Path]::GetFileNameWithoutExtension($Path)
    if ($base -match '^(.*)_24_regular$') { return $Matches[1] }
    return $null
}
Write-Host "fluent ready: $FluentCount icons -> $FluentDest"

# Tabler Icons (@tabler/icons) — outline style.
$TablerWork = Join-Path (Get-ScratchDir) "local-infer-core-tabler-$TablerVersion"
Write-Host "installing @tabler/icons@$TablerVersion ..."
Ensure-NpmPackage -WorkDir $TablerWork -PackageSpec "@tabler/icons@$TablerVersion"
$TablerPkg = Join-Path $TablerWork "node_modules\@tabler\icons"
$TablerCandidates = @(
    (Join-Path $TablerPkg "icons\outline")
    (Join-Path $TablerPkg "categories\outline")
)
$TablerFiles = @()
foreach ($candidate in $TablerCandidates) {
    if (Test-Path $candidate) {
        $TablerFiles += Get-ChildItem -Path $candidate -Recurse -Filter "*.svg" | ForEach-Object { $_.FullName }
    }
}
if ($TablerFiles.Count -eq 0) {
    throw "Tabler SVG source not found under $TablerPkg"
}
$TablerDest = Join-Path $SvgRoot "tabler"
$TablerCount = Copy-FlattenSvg -SourceFiles $TablerFiles -DestDir $TablerDest -NameSelector {
    param($Path)
    return [System.IO.Path]::GetFileNameWithoutExtension($Path)
}
Write-Host "tabler ready: $TablerCount icons -> $TablerDest"

# Font Awesome Free — solid + regular under namespace `fa` (prefix solid-/regular-).
$FaWork = Join-Path (Get-ScratchDir) "local-infer-core-fa-$FaVersion"
Write-Host "installing @fortawesome/fontawesome-free@$FaVersion ..."
Ensure-NpmPackage -WorkDir $FaWork -PackageSpec "@fortawesome/fontawesome-free@$FaVersion"
$FaPkg = Join-Path $FaWork "node_modules\@fortawesome\fontawesome-free"
$FaSolidSrc = Join-Path $FaPkg "svgs\solid"
$FaRegularSrc = Join-Path $FaPkg "svgs\regular"
if (-not (Test-Path $FaSolidSrc)) { throw "Font Awesome solid SVG source not found: $FaSolidSrc" }
if (-not (Test-Path $FaRegularSrc)) { throw "Font Awesome regular SVG source not found: $FaRegularSrc" }

$FaDest = Join-Path $SvgRoot "fa"
$FaSolidCount = Copy-FlattenSvg `
    -SourceFiles ((Get-ChildItem $FaSolidSrc -Filter *.svg | ForEach-Object { $_.FullName })) `
    -DestDir $FaDest `
    -NameSelector {
        param($Path)
        $stem = [System.IO.Path]::GetFileNameWithoutExtension($Path)
        return "solid-$stem"
    }
Write-Host "fa (solid) ready: $FaSolidCount icons -> $FaDest"

$FaRegularAdded = Copy-FlattenSvg `
    -SourceFiles ((Get-ChildItem $FaRegularSrc -Filter *.svg | ForEach-Object { $_.FullName })) `
    -DestDir $FaDest `
    -Append `
    -NameSelector {
        param($Path)
        $stem = [System.IO.Path]::GetFileNameWithoutExtension($Path)
        return "regular-$stem"
    }
Write-Host "fa (regular) added: $FaRegularAdded total in $FaDest"

Write-Host "icon libraries ready under $SvgRoot"

if ($Rasterize) {
    $CliBin = Get-InferCoreHelper -RepoRoot $RepoRoot
    foreach ($ns in @("fluent", "tabler", "fa")) {
        Invoke-RasterizeNamespace -CliBin $CliBin -Namespace $ns -Size $Size -Color $Color -Jobs $Jobs
    }
}
