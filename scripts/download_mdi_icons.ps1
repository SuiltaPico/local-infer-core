# Download Material Design Icons (@mdi/svg) for icon similarity matching.
# SVG is the official distribution; PNG is generated locally via infer-core-helper.
param(
    [string]$Version = "7.4.47",
    [string]$OutDir = (Join-Path (Split-Path $PSScriptRoot -Parent) "assets"),
    [switch]$Rasterize,
    [int]$Size = 48,
    [ValidateSet("black", "white")]
    [string]$Color = "black",
    [int]$Jobs = 0
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "cargo_retry.ps1")
. (Join-Path $PSScriptRoot "icon_assets.ps1")

$RepoRoot = Split-Path $PSScriptRoot -Parent
$WorkDir = Join-Path (Get-ScratchDir) "local-infer-core-mdi-$Version"
$SvgSrc = Join-Path $WorkDir "node_modules\@mdi\svg\svg"
$MetaSrc = Join-Path $WorkDir "node_modules\@mdi\svg\meta.json"
$SvgDest = Join-Path $OutDir "svg/mdi"
$MetaDest = Join-Path $OutDir "meta.json"
$PngDest = Join-Path $OutDir "icons/mdi"

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

if (-not (Test-Path $SvgSrc)) {
    Write-Host "installing @mdi/svg@$Version ..."
    New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
    Push-Location $WorkDir
    try {
        if (-not (Test-Path "package.json")) {
            npm init -y | Out-Null
        }
        npm install "@mdi/svg@$Version" --no-save --silent
    } finally {
        Pop-Location
    }
}

if (-not (Test-Path $SvgSrc)) {
    throw "SVG source not found: $SvgSrc"
}

Write-Host "copying SVG files -> $SvgDest"
if (Test-Path $SvgDest) {
    Remove-Item -Recurse -Force $SvgDest
}
Copy-Item -Recurse $SvgSrc $SvgDest
Copy-Item -Force $MetaSrc $MetaDest

$count = (Get-ChildItem $SvgDest -Filter *.svg).Count
Write-Host "mdi ready: $count icons in $OutDir"
Write-Host "  svg:  $SvgDest"
Write-Host "  meta: $MetaDest"

if ($Rasterize) {
    $CliBin = Get-InferCoreHelper -RepoRoot $RepoRoot
    Invoke-IconRasterizeSvg -CliBin $CliBin -SvgDir $SvgDest -OutDir $PngDest -Size $Size -Color $Color -Jobs $Jobs
    $pngCount = (Get-ChildItem $PngDest -Filter *.png -ErrorAction SilentlyContinue).Count
    Write-Host "png ready: $pngCount files in $PngDest"
}
