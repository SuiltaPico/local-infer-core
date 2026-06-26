# Shared helpers for icon SVG download / PNG rasterization.
. (Join-Path $PSScriptRoot "cargo_retry.ps1")

function Get-IconAssetsRoot {
    param([string]$OutDir = (Join-Path (Split-Path $PSScriptRoot -Parent) "assets"))
    return (Resolve-Path (New-Item -ItemType Directory -Force -Path $OutDir)).Path
}

function Get-InferCoreHelper {
    param([string]$RepoRoot)

    $exeName = if ($IsWindows -or ($env:OS -match "Windows")) {
        "infer-core-helper.exe"
    } else {
        "infer-core-helper"
    }
    $CliBin = Join-Path $RepoRoot (Join-Path "target" (Join-Path "release" $exeName))
    if (-not (Test-Path $CliBin)) {
        Write-Host "building infer-core-helper (release) ..."
        Push-Location $RepoRoot
        try {
            Invoke-CargoWithRetry -Arguments @('build', '-p', 'infer-core', '--release', '--bin', 'infer-core-helper')
        } finally {
            Pop-Location
        }
    }
    if (-not (Test-Path $CliBin)) {
        throw "missing infer-core-helper: $CliBin"
    }
    return $CliBin
}

function Invoke-IconRasterizeSvg {
    param(
        [string]$CliBin,
        [string]$SvgDir,
        [string]$OutDir,
        [int]$Size,
        [string]$Color,
        [int]$Jobs
    )

    $RasterArgs = @(
        "icon", "rasterize-svg",
        "--svg-dir", $SvgDir,
        "--out-dir", $OutDir,
        "--size", $Size,
        "--color", $Color
    )
    if ($Jobs -gt 0) {
        $RasterArgs += @("--jobs", $Jobs)
    }

    Write-Host "rasterizing to $OutDir ($Size px, $Color) ..."
    & $CliBin @RasterArgs
    if ($LASTEXITCODE -gt 0) {
        throw "infer-core-helper icon rasterize-svg failed with exit code $LASTEXITCODE"
    }
}
