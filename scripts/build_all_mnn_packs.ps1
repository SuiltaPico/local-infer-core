# Build all official MNN model packs from existing ONNX fixtures.
# Icon index packs are NOT included — embeddings.bin is format-agnostic.
param(
    [switch]$SkipMedium,
    [switch]$Force
)

$ErrorActionPreference = "Stop"

Write-Host "=== PP-OCRv6 MNN packs ==="
if ($SkipMedium) {
    if ($Force) {
        & (Join-Path $PSScriptRoot "build_ppocr6_mnn_all.ps1") -SkipMedium -Force
    } else {
        & (Join-Path $PSScriptRoot "build_ppocr6_mnn_all.ps1") -SkipMedium
    }
} elseif ($Force) {
    & (Join-Path $PSScriptRoot "build_ppocr6_mnn_all.ps1") -Force
} else {
    & (Join-Path $PSScriptRoot "build_ppocr6_mnn_all.ps1")
}

Write-Host "=== MobileCLIP2 embed MNN packs ==="
if ($Force) {
    & (Join-Path $PSScriptRoot "build_embed_mnn_all.ps1") -Force
} else {
    & (Join-Path $PSScriptRoot "build_embed_mnn_all.ps1")
}

Write-Host "All requested MNN packs ready."
