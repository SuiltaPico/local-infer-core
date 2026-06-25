# Download a PP-OCRv6 ONNX pack into crates/infer-core/tests/fixtures/{pack_id}/
param(
    [Parameter(Mandatory)]
    [ValidateSet("tiny", "small", "medium")]
    [string]$Size,

    [Parameter(Mandatory)]
    [ValidateSet("fp32")]
    [string]$Quant
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\packs\ppocr6.ps1"

$Root = Split-Path $PSScriptRoot -Parent
$FixturesDir = Join-Path $Root "crates\infer-core\tests\fixtures"
$PackId = Get-Ppocr6PackId -Size $Size -Quant $Quant
$PackDir = Join-Path $FixturesDir $PackId
$DictFile = $script:Ppocr6Sizes[$Size].DictFile

New-Item -ItemType Directory -Force -Path $PackDir | Out-Null
Copy-Ppocr6LicenseFiles -PackDir $PackDir
Write-Ppocr6Manifest -PackDir $PackDir -PackId $PackId -Size $Size -Quant $Quant -DictFile $DictFile

$DetDest = Join-Path $PackDir "det.onnx"
$RecDest = Join-Path $PackDir "rec.onnx"
$DictDest = Join-Path $PackDir $DictFile

$DetTar = "$script:Ppocr6BaseUrl/$(Get-Ppocr6DetTarName -Size $Size)"
$RecTar = "$script:Ppocr6BaseUrl/$(Get-Ppocr6RecTarName -Size $Size)"
Extract-Ppocr6OnnxFromTar -TarUrl $DetTar -DestOnnx $DetDest
Extract-Ppocr6OnnxFromTar -TarUrl $RecTar -DestOnnx $RecDest

if (-not (Test-Path $DictDest)) {
    $DictUrl = Get-Ppocr6DictUrl -DictFile $DictFile
    Write-Host "downloading dict: $DictFile"
    Invoke-WebRequest -Uri $DictUrl -OutFile $DictDest
}
else {
    Write-Host "skip (exists): $DictFile"
}

Ensure-Ppocr6SampleImage -FixturesDir $FixturesDir
Write-Host "pack ready: $PackDir ($PackId)"
