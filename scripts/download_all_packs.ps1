# Download all official model packs into fixture layout (OCR + embed; icons optional).
param(
    [switch]$SkipMedium,
    [switch]$SkipIcons,
    [string]$UiExtractorRoot = (Join-Path (Split-Path $PSScriptRoot -Parent) "..\ui-extractor")
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path $PSScriptRoot -Parent

Write-Host "=== PP-OCRv6 packs ==="
& (Join-Path $RepoRoot "download_ppocr6_all.ps1") @(
    if ($SkipMedium) { "-SkipMedium" }
)

Write-Host "=== MobileCLIP2 embed packs ==="
& (Join-Path $RepoRoot "download_embed_all.ps1")

if (-not $SkipIcons) {
    Write-Host "=== icons.bundled packs (this may take several minutes) ==="
    & (Join-Path $RepoRoot "tools\icon-index\build_bundled.ps1") -Quant all -UiExtractorRoot $UiExtractorRoot
}

Write-Host "All requested packs ready."
