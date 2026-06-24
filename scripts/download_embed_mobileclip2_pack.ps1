# Download MobileCLIP2-S0 vision ONNX into an embed pack fixture directory.
param(
    [Parameter(Mandatory)]
    [ValidateSet("int8", "fp32")]
    [string]$Quant,

    [switch]$ReuseFp32Weights
)

$ErrorActionPreference = "Stop"

$Root = Split-Path $PSScriptRoot -Parent
$FixturesDir = Join-Path $Root "crates\infer-core\tests\fixtures"
$PackId = "embed.mobileclip2-s0.onnx.$Quant"
$PackDir = Join-Path $FixturesDir $PackId
$VisionDest = Join-Path $PackDir "vision.onnx"

New-Item -ItemType Directory -Force -Path $PackDir | Out-Null

$shared = Join-Path $Root "packs\shared\embed"
Copy-Item (Join-Path $shared "LICENSE") (Join-Path $PackDir "LICENSE") -Force
Copy-Item (Join-Path $shared "NOTICE") (Join-Path $PackDir "NOTICE") -Force

$manifest = [ordered]@{
    schema    = 1
    id        = $PackId
    kind      = "embed"
    family    = "mobileclip2"
    format    = "onnx"
    quant     = $Quant
    files     = [ordered]@{ vision = "vision.onnx" }
    dim       = 512
    preprocess = [ordered]@{
        input_size = 256
        layout     = "NCHW"
        normalize  = "mobileclip2"
    }
    runtime   = "onnxruntime"
    license   = [ordered]@{
        spdx     = "SEE LICENSE"
        files    = @("LICENSE", "NOTICE")
        upstream = [ordered]@{
            name      = "MobileCLIP2-S0"
            url       = "https://github.com/apple/ml-mobileclip"
            component = "vision encoder weights (converted ONNX)"
        }
    }
}
($manifest | ConvertTo-Json -Depth 6) | Set-Content (Join-Path $PackDir "manifest.json") -Encoding UTF8

if ($ReuseFp32Weights -and $Quant -eq "int8") {
    $src = Join-Path $FixturesDir "embed.mobileclip2-s0.onnx.fp32\vision.onnx"
    if (-not (Test-Path $src)) {
        throw "missing $src — run download_embed_mobileclip2_pack.ps1 -Quant fp32 first"
    }
    Copy-Item $src $VisionDest -Force
    Write-Host "reused vision.onnx from embed.mobileclip2-s0.onnx.fp32"
}
elseif (Test-Path $VisionDest) {
    Write-Host "skip (exists): vision.onnx"
}
else {
    $Url = "https://huggingface.co/plhery/mobileclip2-onnx/resolve/main/onnx/s0/vision_model.onnx"
    Write-Host "downloading: $Url"
    Invoke-WebRequest -Uri $Url -OutFile $VisionDest
}

Write-Host "pack ready: $PackDir ($PackId)"
