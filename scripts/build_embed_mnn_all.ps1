# Convert all official MobileCLIP2-S0 ONNX embed packs to MNN.
param(
    [switch]$Force
)

$ErrorActionPreference = "Stop"

& (Join-Path $PSScriptRoot "build_embed_mnn_pack.ps1") -Quant fp32 -Force:$Force
& (Join-Path $PSScriptRoot "build_embed_mnn_pack.ps1") -Quant int8 -Force:$Force

Write-Host "embed MNN packs ready under crates/infer-core/tests/fixtures/"
