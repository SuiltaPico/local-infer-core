# Download all official PP-OCRv6 ONNX packs (fixture layout).
param(
    [ValidateSet("tiny", "small", "medium", "all")]
    [string[]]$Sizes = @("all"),

    [switch]$SkipMedium
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

& "$PSScriptRoot\download_ppocr6_pack.ps1" -Size tiny -Quant fp32

foreach ($size in $targetSizes) {
    if ($size -eq "tiny") {
        continue
    }
    if ($size -in @("small", "medium")) {
        & "$PSScriptRoot\download_ppocr6_pack.ps1" -Size $size -Quant fp32
    }
}

Write-Host "PP-OCRv6 packs ready under crates/infer-core/tests/fixtures/"
