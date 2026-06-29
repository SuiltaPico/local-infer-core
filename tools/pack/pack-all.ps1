# Validate and zip all official model packs.
param(
    [string]$FixturesRoot,
    [string]$OutDir,
    [switch]$WriteSha256,
    [string[]]$Only = @()
)

$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $RepoRoot "scripts\packs\release.ps1")
$ReleaseRepo = Get-ReleaseRepo
$ReleaseTag = Get-ReleaseTag
if (-not $FixturesRoot) {
    $FixturesRoot = Join-Path $RepoRoot "crates\infer-core\tests\fixtures"
}
if (-not $OutDir) {
    $OutDir = Join-Path $RepoRoot "dist"
}

$OfficialPacks = @(
    # ONNX (desktop)
    "ocr.paddle.ppocr6-tiny.onnx.fp32",
    "ocr.paddle.ppocr6-small.onnx.fp32",
    "ocr.paddle.ppocr6-medium.onnx.fp32",
    "embed.mobileclip2-s0.onnx.fp32",
    "icons.bundled.v1.mobileclip2-s0.int8",
    "icons.bundled.v1.mobileclip2-s0.fp32",
    # MNN (mobile)
    "ocr.paddle.ppocr6-tiny.mnn.fp32",
    "ocr.paddle.ppocr6-small.mnn.fp32",
    "ocr.paddle.ppocr6-medium.mnn.fp32",
    "embed.mobileclip2-s0.mnn.int8",
    "embed.mobileclip2-s0.mnn.fp32"
)

$FixturesRoot = Resolve-Path $FixturesRoot
$PackScript = Join-Path $PSScriptRoot "pack.ps1"
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$targets = if ($Only.Count -gt 0) { $Only } else { $OfficialPacks }

foreach ($packId in $targets) {
    $packDir = Join-Path $FixturesRoot $packId
    if (-not (Test-Path $packDir)) {
        Write-Warning "skip missing pack dir: $packDir"
        continue
    }

    $zipPath = Join-Path $OutDir "$packId.zip"
    & $PackScript -PackDir $packDir -OutZip $zipPath
    if ($? -ne $true) { throw "pack failed: $packId" }
}

if ($WriteSha256) {
    $shaPath = Join-Path $OutDir "SHA256SUMS.txt"
    $shaLines = Get-ChildItem $OutDir -Filter "*.zip" | Sort-Object Name | ForEach-Object {
        $hash = (Get-FileHash -Path $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        "$hash  $($_.Name)"
    }
    if ($shaLines.Count -gt 0) {
        Set-Content -Path $shaPath -Value ($shaLines -join "`n") -Encoding UTF8
        Write-Host "wrote $shaPath ($($shaLines.Count) zips)"
    }
}

Write-Host "pack-all done ($($targets.Count) requested, output: $OutDir)"
