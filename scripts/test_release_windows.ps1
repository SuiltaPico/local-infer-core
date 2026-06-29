# Smoke-test packaged infer-core Windows release zips (layout + FFI + optional OCR).
param(
    [ValidateSet("x86_64", "aarch64", "all")]
    [string]$Arch = "x86_64",
    [string]$DistDir = "dist",
    [switch]$SkipOcr
)
$ErrorActionPreference = "Stop"

$Root = Split-Path $PSScriptRoot -Parent
$DistDir = if ([IO.Path]::IsPathRooted($DistDir)) { $DistDir } else { Join-Path $Root $DistDir }
$FixturesDir = Join-Path $Root "crates\infer-core\tests\fixtures"
$PackId = "ocr.paddle.ppocr6-tiny.onnx.fp32"
$SampleImage = Join-Path $FixturesDir "sample_ocr.jpg"

$archLabels = if ($Arch -eq "all") {
    @("x86_64", "aarch64")
} else {
    @($Arch)
}

function Test-InferCoreZip {
    param(
        [string]$Label,
        [string]$ZipPath
    )

    if (-not (Test-Path $ZipPath)) {
        throw "Release zip not found: $ZipPath (run scripts/build_release_windows.ps1 first)"
    }

    $stage = Join-Path $env:TEMP "infer-core-smoke-$Label"
    if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
    Expand-Archive -Path $ZipPath -DestinationPath $stage -Force

    $dll = Join-Path $stage "lib\infer_core.dll"
    if (-not (Test-Path $dll)) {
        throw "Zip layout invalid (expected lib/infer_core.dll): $ZipPath"
    }

    $sizeMb = [math]::Round((Get-Item $dll).Length / 1MB, 2)
    Write-Host "[$Label] lib/infer_core.dll ($sizeMb MB)"

    $libDir = Split-Path $dll -Parent
    $prevCwd = [Environment]::CurrentDirectory
    [Environment]::CurrentDirectory = $libDir
    try {
        Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class InferCoreReleaseSmoke {
    [DllImport("infer_core.dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern IntPtr infer_core_version();
    [DllImport("infer_core.dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern IntPtr infer_registry_create(IntPtr modelsDir, IntPtr runtimeJson, out IntPtr outError);
    [DllImport("infer_core.dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern void infer_registry_destroy(IntPtr handle);
    [DllImport("infer_core.dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern IntPtr infer_ocr_engine_load(IntPtr handle, IntPtr packId, out IntPtr outError);
    [DllImport("infer_core.dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern void infer_ocr_engine_destroy(IntPtr engine);
    [DllImport("infer_core.dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern int infer_ocr_recognize_timed(
        IntPtr engine, byte[] data, UIntPtr len, out IntPtr outJson, out IntPtr outError);
    [DllImport("infer_core.dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern void infer_string_free(IntPtr s);
}
"@

        $ver = [Runtime.InteropServices.Marshal]::PtrToStringAnsi(
            [InferCoreReleaseSmoke]::infer_core_version())
        if ([string]::IsNullOrWhiteSpace($ver)) {
            throw "infer_core_version returned empty"
        }
        Write-Host "[$Label] version: $ver"

        $modelsPtr = [Runtime.InteropServices.Marshal]::StringToHGlobalAnsi($FixturesDir)
        $regErr = [IntPtr]::Zero
        $handle = [InferCoreReleaseSmoke]::infer_registry_create($modelsPtr, [IntPtr]::Zero, [ref]$regErr)
        [Runtime.InteropServices.Marshal]::FreeHGlobal($modelsPtr)
        if ($handle -eq [IntPtr]::Zero) {
            $msg = [Runtime.InteropServices.Marshal]::PtrToStringAnsi($regErr)
            [InferCoreReleaseSmoke]::infer_string_free($regErr)
            throw "infer_registry_create failed: $msg"
        }
        if ($regErr -ne [IntPtr]::Zero) {
            [InferCoreReleaseSmoke]::infer_string_free($regErr)
        }

        if (-not $SkipOcr) {
            $packDir = Join-Path $FixturesDir $PackId
            $weightsReady = @("det.onnx", "rec.onnx", "ppocrv6_tiny_dict.txt") | ForEach-Object {
                Test-Path (Join-Path $packDir $_)
            } | Where-Object { $_ -eq $false } | Measure-Object | Select-Object -ExpandProperty Count
            if ($weightsReady -gt 0 -or -not (Test-Path $SampleImage)) {
                Write-Warning "[$Label] skip OCR: run scripts/download_ppocr6_tiny_fixture.ps1 for full OCR smoke"
            } else {
                $bytes = [IO.File]::ReadAllBytes($SampleImage)
                $packPtr = [Runtime.InteropServices.Marshal]::StringToHGlobalAnsi($PackId)
                $engineErr = [IntPtr]::Zero
                $engine = [InferCoreReleaseSmoke]::infer_ocr_engine_load($handle, $packPtr, [ref]$engineErr)
                [Runtime.InteropServices.Marshal]::FreeHGlobal($packPtr)
                if ($engine -eq [IntPtr]::Zero) {
                    $msg = [Runtime.InteropServices.Marshal]::PtrToStringAnsi($engineErr)
                    if ($engineErr -ne [IntPtr]::Zero) { [InferCoreReleaseSmoke]::infer_string_free($engineErr) }
                    throw "infer_ocr_engine_load failed: $msg"
                }
                if ($engineErr -ne [IntPtr]::Zero) { [InferCoreReleaseSmoke]::infer_string_free($engineErr) }

                $jsonPtr = [IntPtr]::Zero
                $outErr = [IntPtr]::Zero
                $rc = [InferCoreReleaseSmoke]::infer_ocr_recognize_timed(
                    $engine, $bytes, [UIntPtr]::new($bytes.Length), [ref]$jsonPtr, [ref]$outErr)
                [InferCoreReleaseSmoke]::infer_ocr_engine_destroy($engine)
                if ($rc -ne 0) {
                    $msg = if ($outErr -ne [IntPtr]::Zero) {
                        [Runtime.InteropServices.Marshal]::PtrToStringAnsi($outErr)
                    } else { "unknown error" }
                    if ($outErr -ne [IntPtr]::Zero) { [InferCoreReleaseSmoke]::infer_string_free($outErr) }
                    throw "infer_ocr_recognize_timed failed (rc=$rc): $msg"
                }
                $json = [Runtime.InteropServices.Marshal]::PtrToStringAnsi($jsonPtr)
                [InferCoreReleaseSmoke]::infer_string_free($jsonPtr)
                if ($outErr -ne [IntPtr]::Zero) { [InferCoreReleaseSmoke]::infer_string_free($outErr) }
                if ([string]::IsNullOrWhiteSpace($json) -or $json -notmatch '"text"') {
                    throw "infer_ocr_recognize_timed returned empty or invalid JSON"
                }
                $preview = if ($json.Length -gt 60) { $json.Substring(0, 60) + "..." } else { $json }
                Write-Host "[$Label] OCR ok: $preview"
            }
        }

        [InferCoreReleaseSmoke]::infer_registry_destroy($handle)
    } finally {
        [Environment]::CurrentDirectory = $prevCwd
        # DLL stays locked until this PowerShell process exits (Add-Type); stage dir is reused next run.
    }

    Write-Host "[$Label] smoke test passed"
}

Push-Location $Root
try {
    foreach ($label in $archLabels) {
        $zip = Join-Path $DistDir "infer-core-windows-$label.zip"
        Test-InferCoreZip -Label $label -ZipPath $zip
    }
    Write-Host "All release smoke tests passed."
} finally {
    Pop-Location
}
