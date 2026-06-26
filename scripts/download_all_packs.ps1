# Download all official model packs into fixture layout (OCR + embed; icons optional).
param(
    [switch]$SkipMedium,
    [switch]$SkipIcons,
    [switch]$SkipMnn,
    [switch]$ForceMnn
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path $PSScriptRoot -Parent

Write-Host "=== PP-OCRv6 packs ==="
& (Join-Path $PSScriptRoot "download_ppocr6_all.ps1") @(
    if ($SkipMedium) { "-SkipMedium" }
)

Write-Host "=== MobileCLIP2 embed packs ==="
& (Join-Path $PSScriptRoot "download_embed_all.ps1")

if (-not $SkipIcons) {
    Write-Host "=== icons.bundled packs (this may take several minutes) ==="
    & (Join-Path $RepoRoot "tools\icon-index\build_bundled.ps1") -Quant all
}

if (-not $SkipMnn) {
    Write-Host "=== MNN packs (ONNX -> MNN conversion) ==="
    $mnnBuildArgs = @{}
    if ($SkipMedium) { $mnnBuildArgs.SkipMedium = $true }
    if ($ForceMnn) { $mnnBuildArgs.Force = $true }
    & (Join-Path $PSScriptRoot "build_all_mnn_packs.ps1") @mnnBuildArgs
}

Write-Host "All requested packs ready."
