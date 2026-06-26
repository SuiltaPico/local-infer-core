# Package Android infer-core-ffi .so files for GitHub Releases.
param(
    [string]$OutDir = "dist",
    [switch]$SkipBuild,
    [switch]$SkipPack,
    [switch]$DownloadMnn
)
$ErrorActionPreference = "Stop"

$Root = Split-Path $PSScriptRoot -Parent
Push-Location $Root
try {
    if (-not $SkipBuild) {
        $buildArgs = @{ Abi = "all" }
        if ($DownloadMnn) { $buildArgs.DownloadMnn = $true }
        & (Join-Path $PSScriptRoot "build_android.ps1") @buildArgs
        if ($LASTEXITCODE -gt 0) { exit $LASTEXITCODE }
    }

    if ($SkipPack) {
        Write-Host "SkipPack set; .so files left under android/jniLibs/"
        return
    }

    New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

    $abis = @(
        @{ Name = "arm64-v8a"; Label = "android-arm64-v8a" },
        @{ Name = "x86_64"; Label = "android-x86_64" }
    )

    foreach ($abi in $abis) {
        $jniSrc = Join-Path $Root "android\jniLibs\$($abi.Name)"
        $inferSo = Join-Path $jniSrc "libinfer_core.so"
        if (-not (Test-Path $inferSo)) { throw "Missing build output: $inferSo" }

        $stage = Join-Path $OutDir "infer-core-$($abi.Label)"
        $stageJni = Join-Path $stage "jniLibs\$($abi.Name)"
        New-Item -ItemType Directory -Force -Path $stageJni | Out-Null

        Get-ChildItem $jniSrc -Filter "*.so" | ForEach-Object {
            Copy-Item $_.FullName (Join-Path $stageJni $_.Name) -Force
        }

        $zip = Join-Path $OutDir "infer-core-$($abi.Label).zip"
        if (Test-Path $zip) { Remove-Item -Force $zip }
        Compress-Archive -Path "$stage/*" -DestinationPath $zip -Force
        Remove-Item -Recurse -Force $stage

        $sizeMb = [math]::Round((Get-Item $inferSo).Length / 1MB, 2)
        $libCount = (Get-ChildItem $jniSrc -Filter "*.so").Count
        Write-Host "Packaged: $zip ($sizeMb MB infer_core + $libCount .so files)"
    }
} finally {
    Pop-Location
}
