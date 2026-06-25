# Download official MobileCLIP2-S0 ONNX embed pack (fp32 only on ONNX/desktop).
$ErrorActionPreference = "Stop"

& "$PSScriptRoot\download_embed_mobileclip2_pack.ps1" -Quant fp32

Write-Host "embed pack ready under crates/infer-core/tests/fixtures/"
