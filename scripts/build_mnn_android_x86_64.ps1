# Build shared libMNN.so for Android x86_64 (emulator) — no official prebuilt release.
param(
    [string]$Version = "3.6.0"
)
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "cargo_retry.ps1")

$Root = Split-Path $PSScriptRoot -Parent
$SourceRoot = Join-Path $Root "third_party\mnn\source"
$OutAbiDir = Join-Path $Root "third_party\mnn\android\x86_64"
$LibMnn = Join-Path $OutAbiDir "libMNN.so"

if (Test-Path $LibMnn) {
    Write-Host "MNN x86_64 shared lib already present: $LibMnn"
    return
}

if (-not (Test-Path (Join-Path $SourceRoot "CMakeLists.txt"))) {
    & (Join-Path $PSScriptRoot "download_mnn_android.ps1") -Abi arm64-v8a | Out-Null
}

function Resolve-NdkHome {
    foreach ($candidate in @($env:ANDROID_NDK_HOME, $env:NDK_HOME)) {
        if ($candidate -and (Test-Path $candidate)) { return $candidate }
    }
    $SdkNdk = Join-Path $env:LOCALAPPDATA "Android\Sdk\ndk"
    if (Test-Path $SdkNdk) {
        $latest = Get-ChildItem $SdkNdk -Directory | Sort-Object Name -Descending | Select-Object -First 1
        if ($latest) { return $latest.FullName }
    }
    throw "Android NDK not found. Set ANDROID_NDK_HOME or install NDK via Android Studio."
}

function Resolve-AndroidBuildTool {
    param([string]$Name)

    $SdkCmakeRoot = Join-Path $env:LOCALAPPDATA "Android\Sdk\cmake"
    if (Test-Path $SdkCmakeRoot) {
        $latest = Get-ChildItem $SdkCmakeRoot -Directory | Sort-Object Name -Descending | Select-Object -First 1
        if ($latest) {
            $candidate = Join-Path $latest.FullName "bin\$Name.exe"
            if (Test-Path $candidate) { return $candidate }
        }
    }

    foreach ($candidate in @(
        "C:\Program Files\CMake\bin\$Name.exe",
        "C:\Program Files (x86)\CMake\bin\$Name.exe"
    )) {
        if (Test-Path $candidate) { return $candidate }
    }

    $onPath = Get-Command $Name -ErrorAction SilentlyContinue
    if ($onPath) { return $onPath.Source }

    throw "$Name not found. Install Android SDK CMake (sdkmanager `"cmake;3.22.1`") or add $Name to PATH."
}

function Resolve-NdkLibcxxShared {
    param(
        [string]$NdkHome,
        [string]$Triple
    )

    $hostTag = if ($IsWindows -or $env:OS -eq "Windows_NT") { "windows-x86_64" } else { "linux-x86_64" }
    $candidate = Join-Path $NdkHome "toolchains\llvm\prebuilt\$hostTag\sysroot\usr\lib\$Triple\libc++_shared.so"
    if (-not (Test-Path $candidate)) {
        throw "NDK libc++_shared.so not found: $candidate"
    }
    return $candidate
}

$NdkHome = Resolve-NdkHome
$Toolchain = Join-Path $NdkHome "build\cmake\android.toolchain.cmake"
if (-not (Test-Path $Toolchain)) {
    throw "NDK cmake toolchain not found: $Toolchain"
}

$BuildDir = Join-Path (Get-ScratchDir) "mnn-x86_64-android-build"
$InstallDir = Join-Path (Get-ScratchDir) "mnn-x86_64-android-install"
if (Test-Path $BuildDir) { Remove-Item -Recurse -Force $BuildDir }
if (Test-Path $InstallDir) { Remove-Item -Recurse -Force $InstallDir }

$Cmake = Resolve-AndroidBuildTool -Name "cmake"
$Ninja = Resolve-AndroidBuildTool -Name "ninja"

Write-Host "Building shared libMNN.so for Android x86_64 (MNN $Version)..."
Write-Host "NDK: $NdkHome"
Write-Host "CMake: $Cmake"
Write-Host "Ninja: $Ninja"

$cmakeArgs = @(
    "-S", $SourceRoot,
    "-B", $BuildDir,
    "-G", "Ninja",
    "-DCMAKE_MAKE_PROGRAM=$Ninja",
    "-DCMAKE_TOOLCHAIN_FILE=$Toolchain",
    "-DANDROID_ABI=x86_64",
    "-DANDROID_PLATFORM=android-24",
    "-DCMAKE_BUILD_TYPE=Release",
    "-DCMAKE_INSTALL_PREFIX=$InstallDir",
    "-DMNN_BUILD_SHARED_LIBS=ON",
    "-DMNN_SEP_BUILD=OFF",
    "-DMNN_PORTABLE_BUILD=ON",
    "-DMNN_BUILD_CONVERTER=OFF",
    "-DMNN_BUILD_TOOLS=OFF",
    "-DMNN_BUILD_FOR_ANDROID_COMMAND=ON",
    "-DMNN_USE_THREAD_POOL=ON",
    "-DMNN_OPENCL=OFF",
    "-DMNN_VULKAN=OFF",
    "-DMNN_BUILD_LLM=OFF",
    "-DMNN_BUILD_DIFFUSION=OFF",
    "-DMNN_BUILD_AUDIO=OFF",
    "-DMNN_BUILD_OPENCV=OFF"
)

& $Cmake @cmakeArgs
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& $Cmake --build $BuildDir --target install -j
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$installLibDir = Join-Path $InstallDir "lib"
$builtLib = Join-Path $installLibDir "libMNN.so"
if (-not (Test-Path $builtLib)) {
    throw "Expected shared library not found after install: $builtLib"
}

New-Item -ItemType Directory -Force -Path $OutAbiDir | Out-Null
$legacyStaticDir = Join-Path $OutAbiDir "lib"
if (Test-Path $legacyStaticDir) {
    Remove-Item -Recurse -Force $legacyStaticDir
}
Get-ChildItem $installLibDir -Filter "*.so" | ForEach-Object {
    Copy-Item $_.FullName (Join-Path $OutAbiDir $_.Name) -Force
}

$LibcxxShared = Resolve-NdkLibcxxShared -NdkHome $NdkHome -Triple "x86_64-linux-android"
Copy-Item $LibcxxShared (Join-Path $OutAbiDir "libc++_shared.so") -Force

Write-Host "Installed: third_party/mnn/android/x86_64/libMNN.so"
