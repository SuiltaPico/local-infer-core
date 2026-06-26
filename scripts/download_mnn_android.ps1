# Download MNN 3.6.0 headers + official Android prebuilt shared libraries (arm64-v8a / armeabi-v7a).
param(
    [string]$Version = "3.6.0",
    [ValidateSet("arm64-v8a", "armeabi-v7a", "all")]
    [string]$Abi = "all"
)
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "cargo_retry.ps1")

$Root = Split-Path $PSScriptRoot -Parent
$MnnRoot = Join-Path $Root "third_party\mnn"
$AndroidRoot = Join-Path $MnnRoot "android"
$SourceRoot = Join-Path $MnnRoot "source"

$PrebuiltUrl = "https://github.com/alibaba/MNN/releases/download/$Version/mnn_${Version}_android_armv7_armv8_cpu_opencl_vulkan.zip"
$SourceUrl = "https://github.com/alibaba/MNN/archive/refs/tags/$Version.zip"

$Abis = if ($Abi -eq "all") { @("arm64-v8a", "armeabi-v7a") } else { @($Abi) }

function Test-MnnSourceReady {
    Test-Path (Join-Path $SourceRoot "include\MNN\Interpreter.hpp")
}

function Test-MnnPrebuiltReady {
    param([string]$Name)
    Test-Path (Join-Path $AndroidRoot "$Name\libMNN.so")
}

if (-not (Test-MnnSourceReady)) {
    $zipPath = Join-Path (Get-ScratchDir) "MNN-$Version-source.zip"
    $extractRoot = Join-Path (Get-ScratchDir) "MNN-$Version-source-extract"

    Write-Host "Downloading MNN $Version source headers..."
    Invoke-WebRequest -Uri $SourceUrl -OutFile $zipPath

    if (Test-Path $extractRoot) { Remove-Item -Recurse -Force $extractRoot }
    Expand-Archive -Path $zipPath -DestinationPath $extractRoot -Force

    $extracted = Join-Path $extractRoot "MNN-$Version"
    if (-not (Test-Path $extracted)) {
        $dirs = @(Get-ChildItem $extractRoot -Directory -ErrorAction SilentlyContinue)
        if ($dirs.Count -eq 1) {
            $extracted = $dirs[0].FullName
        } else {
            throw "Unexpected MNN source archive layout (missing MNN-$Version)"
        }
    }

    if (Test-Path $SourceRoot) { Remove-Item -Recurse -Force $SourceRoot }
    New-Item -ItemType Directory -Force -Path (Split-Path $SourceRoot -Parent) | Out-Null
    Copy-Item -Recurse -Force $extracted $SourceRoot
    Write-Host "Installed MNN source headers: third_party/mnn/source/"
}

$missingPrebuilt = @($Abis | Where-Object { -not (Test-MnnPrebuiltReady $_) })
if ($missingPrebuilt.Count -gt 0) {
    $zipPath = Join-Path (Get-ScratchDir) "mnn_${Version}_android.zip"
    $extractRoot = Join-Path (Get-ScratchDir) "mnn_${Version}_android-extract"

    Write-Host "Downloading MNN $Version Android prebuilt libraries..."
    Invoke-WebRequest -Uri $PrebuiltUrl -OutFile $zipPath

    if (Test-Path $extractRoot) { Remove-Item -Recurse -Force $extractRoot }
    Expand-Archive -Path $zipPath -DestinationPath $extractRoot -Force

    $sourceRoot = Join-Path $extractRoot "mnn_${Version}_android_armv7_armv8_cpu_opencl_vulkan"
    if (-not (Test-Path $sourceRoot)) {
        throw "Unexpected MNN Android archive layout (missing $sourceRoot)"
    }

    New-Item -ItemType Directory -Force -Path $AndroidRoot | Out-Null
    foreach ($name in $missingPrebuilt) {
        $src = Join-Path $sourceRoot $name
        $dest = Join-Path $AndroidRoot $name
        if (-not (Test-Path (Join-Path $src "libMNN.so"))) {
            throw "MNN Android archive missing ABI: $name"
        }
        if (Test-Path $dest) { Remove-Item -Recurse -Force $dest }
        Copy-Item -Recurse $src $dest
        Write-Host "Installed: third_party/mnn/android/$name/"
    }
}

Write-Host "MNN Android artifacts ready (version $Version)."
