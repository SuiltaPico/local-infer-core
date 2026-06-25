# Convert all official PP-OCRv6 ONNX packs to MNN fp32.
param(
    [ValidateSet("tiny", "small", "medium", "all")]
    [string[]]$Sizes = @("all"),

    [switch]$SkipMedium,
    [switch]$Force
)

$ErrorActionPreference = "Stop"

$targetSizes = if ($Sizes -contains "all") {
    @("tiny", "small", "medium")
} else {
    $Sizes
}

if ($SkipMedium) {
    $targetSizes = $targetSizes | Where-Object { $_ -ne "medium" }
}

foreach ($size in $targetSizes) {
    & (Join-Path $PSScriptRoot "build_ppocr6_mnn_pack.ps1") -Size $size -Force:$Force
}

Write-Host "PP-OCRv6 MNN packs ready under crates/infer-core/tests/fixtures/"
