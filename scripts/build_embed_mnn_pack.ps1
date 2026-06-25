# Convert an existing MobileCLIP2-S0 ONNX embed fixture pack to MNN.
param(
    [Parameter(Mandatory)]
    [ValidateSet("int8", "fp32")]
    [string]$Quant,

    [switch]$Force
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\packs\mnn.ps1"

$Root = Split-Path $PSScriptRoot -Parent
$FixturesDir = Join-Path $Root "crates\infer-core\tests\fixtures"
$OnnxPackId = "embed.mobileclip2-s0.onnx.fp32"
$MnnPackId = "embed.mobileclip2-s0.mnn.$Quant"
$OnnxDir = Join-Path $FixturesDir $OnnxPackId
$MnnDir = Join-Path $FixturesDir $MnnPackId
$OnnxVision = Join-Path $OnnxDir "vision.onnx"
$MnnVision = Join-Path $MnnDir "vision.mnn"

if (-not (Test-Path $OnnxVision)) {
    Write-Host "ONNX embed pack missing — downloading $OnnxPackId"
    & (Join-Path $PSScriptRoot "download_embed_mobileclip2_pack.ps1") -Quant fp32
}

New-Item -ItemType Directory -Force -Path $MnnDir | Out-Null

$shared = Join-Path $Root "packs\shared\embed"
Copy-Item (Join-Path $shared "LICENSE") (Join-Path $MnnDir "LICENSE") -Force
Copy-Item (Join-Path $shared "NOTICE") (Join-Path $MnnDir "NOTICE") -Force

$manifest = [ordered]@{
    schema     = 1
    id         = $MnnPackId
    kind       = "embed"
    family     = "mobileclip2"
    format     = "mnn"
    quant      = $Quant
    files      = [ordered]@{ vision = "vision.mnn" }
    dim        = 512
    preprocess = [ordered]@{
        input_size = 256
        layout     = "NCHW"
        normalize  = "mobileclip2"
    }
    runtime    = "mnn"
    license    = [ordered]@{
        spdx     = "SEE LICENSE"
        files    = @("LICENSE", "NOTICE")
        upstream = [ordered]@{
            name      = "MobileCLIP2-S0"
            url       = "https://github.com/apple/ml-mobileclip"
            component = "vision encoder weights (ONNX converted to MNN)"
        }
    }
}
($manifest | ConvertTo-Json -Depth 6) | Set-Content (Join-Path $MnnDir "manifest.json") -Encoding UTF8

$weightBits = if ($Quant -eq "int8") { 8 } else { 0 }
Convert-OnnxToMnn -OnnxPath $OnnxVision -MnnPath $MnnVision -WeightQuantBits $weightBits -Force:$Force

Write-Host "pack ready: $MnnDir ($MnnPackId)"
