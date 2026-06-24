# Download all official embed packs (MobileCLIP2-S0 ONNX).
$ErrorActionPreference = "Stop"

& "$PSScriptRoot\download_embed_mobileclip2_pack.ps1" -Quant fp32
& "$PSScriptRoot\download_embed_mobileclip2_pack.ps1" -Quant int8 -ReuseFp32Weights

Write-Host "embed packs ready under crates/infer-core/tests/fixtures/"
