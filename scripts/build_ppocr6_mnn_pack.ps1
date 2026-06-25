# Convert an existing PP-OCRv6 ONNX fixture pack to MNN (det/rec + manifest).
param(
    [Parameter(Mandatory)]
    [ValidateSet("tiny", "small", "medium")]
    [string]$Size,

    [ValidateSet("fp32")]
    [string]$Quant = "fp32",

    [switch]$Force
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\packs\ppocr6.ps1"
. "$PSScriptRoot\packs\mnn.ps1"

$Root = Split-Path $PSScriptRoot -Parent
$FixturesDir = Join-Path $Root "crates\infer-core\tests\fixtures"
$OnnxPackId = Get-Ppocr6PackId -Size $Size -Quant $Quant -Format onnx
$MnnPackId = Get-Ppocr6PackId -Size $Size -Quant $Quant -Format mnn
$OnnxDir = Join-Path $FixturesDir $OnnxPackId
$MnnDir = Join-Path $FixturesDir $MnnPackId
$DictFile = $script:Ppocr6Sizes[$Size].DictFile

if (-not (Test-Path $OnnxDir)) {
    Write-Host "ONNX pack missing — downloading $OnnxPackId"
    & (Join-Path $PSScriptRoot "download_ppocr6_pack.ps1") -Size $Size -Quant $Quant
}

New-Item -ItemType Directory -Force -Path $MnnDir | Out-Null
Copy-Ppocr6LicenseFiles -PackDir $MnnDir
Write-Ppocr6Manifest -PackDir $MnnDir -PackId $MnnPackId -Size $Size -Quant $Quant -DictFile $DictFile -Format mnn

$DictSrc = Join-Path $OnnxDir $DictFile
$DictDest = Join-Path $MnnDir $DictFile
if (-not (Test-Path $DictDest)) {
    Copy-Item $DictSrc $DictDest -Force
}

Convert-OnnxToMnn -OnnxPath (Join-Path $OnnxDir "det.onnx") -MnnPath (Join-Path $MnnDir "det.mnn") -Force:$Force
Convert-OnnxToMnn -OnnxPath (Join-Path $OnnxDir "rec.onnx") -MnnPath (Join-Path $MnnDir "rec.mnn") -Force:$Force

Write-Host "pack ready: $MnnDir ($MnnPackId)"
