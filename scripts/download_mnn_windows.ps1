# Download MNN 3.6.0 source headers + official Windows x64 prebuilt (Dynamic /MD).
param(
    [string]$Version = "3.6.0",
    [string]$ImportFrom = ""
)
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "cargo_retry.ps1")

$Root = Split-Path $PSScriptRoot -Parent
$MnnRoot = Join-Path $Root "third_party\mnn"
$WindowsRoot = Join-Path $MnnRoot "windows\x64-md"
$SourceRoot = Join-Path $MnnRoot "source"

$PrebuiltUrl = "https://github.com/alibaba/MNN/releases/download/$Version/mnn_${Version}_windows_x64_cpu_opencl_vulkan_avx512.zip"
$SourceUrl = "https://github.com/alibaba/MNN/archive/refs/tags/$Version.zip"

function Test-MnnSourceReady {
    Test-Path (Join-Path $SourceRoot "include\MNN\Interpreter.hpp")
}

function Test-MnnWindowsPrebuiltReady {
    $lib = Join-Path $WindowsRoot "MNN.lib"
    $dll = Join-Path $WindowsRoot "MNN.dll"
    if (-not (Test-Path $lib)) { return $false }
    if (-not (Test-Path $dll)) { return $false }
    # Dynamic import lib is tiny; static monolithic lib is hundreds of MB.
    (Get-Item $lib).Length -lt 10MB
}

function Install-MnnSource {
    if (Test-MnnSourceReady) { return }

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

function Install-MnnWindowsPrebuilt {
    if (Test-MnnWindowsPrebuiltReady) { return }

    New-Item -ItemType Directory -Force -Path $WindowsRoot | Out-Null
    Remove-Item -Force (Join-Path $WindowsRoot "MNN.lib") -ErrorAction SilentlyContinue
    Remove-Item -Force (Join-Path $WindowsRoot "MNN.dll") -ErrorAction SilentlyContinue
    Remove-Item -Force (Join-Path $WindowsRoot "MNN.pdb") -ErrorAction SilentlyContinue

    if ($ImportFrom -and (Test-Path $ImportFrom)) {
        $libDir = Join-Path $ImportFrom "lib\x64\Release\Dynamic\MD"
        if (-not (Test-Path (Join-Path $libDir "MNN.lib"))) {
            throw "ImportFrom missing Dynamic/MD MNN.lib: $libDir"
        }
        Copy-Item -Force (Join-Path $libDir "MNN.lib") $WindowsRoot
        Copy-Item -Force (Join-Path $libDir "MNN.dll") $WindowsRoot
        if (Test-Path (Join-Path $libDir "MNN.pdb")) {
            Copy-Item -Force (Join-Path $libDir "MNN.pdb") $WindowsRoot
        }
        Write-Host "Imported Windows Dynamic/MD prebuilt from: $ImportFrom"
        return
    }

    $zipPath = Join-Path (Get-ScratchDir) "mnn_${Version}_windows_x64.zip"
    $extractRoot = Join-Path (Get-ScratchDir) "mnn_${Version}_windows_x64-extract"

    Write-Host "Downloading MNN $Version Windows prebuilt libraries..."
    Invoke-WebRequest -Uri $PrebuiltUrl -OutFile $zipPath

    if (Test-Path $extractRoot) { Remove-Item -Recurse -Force $extractRoot }
    Expand-Archive -Path $zipPath -DestinationPath $extractRoot -Force

    $sourceRoot = Join-Path $extractRoot "mnn_${Version}_windows_x64_cpu_opencl_vulkan_avx512"
    if (-not (Test-Path $sourceRoot)) {
        throw "Unexpected MNN Windows archive layout (missing $sourceRoot)"
    }

    $libDir = Join-Path $sourceRoot "lib\x64\Release\Dynamic\MD"
    if (-not (Test-Path (Join-Path $libDir "MNN.lib"))) {
        throw "MNN Windows archive missing Dynamic/MD libs"
    }

    Copy-Item -Force (Join-Path $libDir "MNN.lib") $WindowsRoot
    Copy-Item -Force (Join-Path $libDir "MNN.dll") $WindowsRoot
    if (Test-Path (Join-Path $libDir "MNN.pdb")) {
        Copy-Item -Force (Join-Path $libDir "MNN.pdb") $WindowsRoot
    }
    Write-Host "Installed: third_party/mnn/windows/x64-md/ (Dynamic/MD MNN.dll + import lib)"
}

Install-MnnSource
Install-MnnWindowsPrebuilt

Write-Host "MNN Windows artifacts ready (version $Version)."
Write-Host "Windows backend-mnn uses prebuilt MNN automatically (MNN_COMPILE=0, MNN_LINK=dylib)."
