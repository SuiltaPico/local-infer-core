# Validate and zip all official model packs.
param(
    [string]$FixturesRoot,
    [string]$OutDir,
    [switch]$WriteSha256,
    [switch]$UpdateCatalog,
    [string[]]$Only = @()
)

$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
if (-not $FixturesRoot) {
    $FixturesRoot = Join-Path $RepoRoot "crates\infer-core\tests\fixtures"
}
if (-not $OutDir) {
    $OutDir = Join-Path $RepoRoot "dist"
}

$OfficialPacks = @(
    "ocr.paddle.ppocr6-tiny.onnx.fp32",
    "ocr.paddle.ppocr6-small.onnx.fp32",
    "ocr.paddle.ppocr6-medium.onnx.fp32",
    "embed.mobileclip2-s0.onnx.int8",
    "embed.mobileclip2-s0.onnx.fp32",
    "icons.bundled.v1.mobileclip2-s0.int8",
    "icons.bundled.v1.mobileclip2-s0.fp32"
)

$FixturesRoot = Resolve-Path $FixturesRoot
$PackScript = Join-Path $PSScriptRoot "pack.ps1"
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$targets = if ($Only.Count -gt 0) { $Only } else { $OfficialPacks }
$shaLines = @()
$catalogPacks = @()

foreach ($packId in $targets) {
    $packDir = Join-Path $FixturesRoot $packId
    if (-not (Test-Path $packDir)) {
        Write-Warning "skip missing pack dir: $packDir"
        continue
    }

    $zipPath = Join-Path $OutDir "$packId.zip"
    & $PackScript -PackDir $packDir -OutZip $zipPath
    if ($? -ne $true) { throw "pack failed: $packId" }

    if ($WriteSha256) {
        $hash = (Get-FileHash -Path $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
        $shaLines += "$hash  $(Split-Path $zipPath -Leaf)"
        $size = (Get-Item $zipPath).Length
        $catalogPacks += [ordered]@{
            id         = $packId
            size_bytes = $size
            sha256     = $hash
        }
    }
}

if ($WriteSha256 -and $shaLines.Count -gt 0) {
    $shaPath = Join-Path $OutDir "SHA256SUMS.txt"
    Set-Content -Path $shaPath -Value ($shaLines -join "`n") -Encoding UTF8
    Write-Host "wrote $shaPath"
}

if ($UpdateCatalog -and $catalogPacks.Count -gt 0) {
    $catalogPath = Join-Path $RepoRoot "dart\assets\catalog.json"
    $existing = @{}
    if (Test-Path $catalogPath) {
        $parsed = Get-Content $catalogPath -Raw | ConvertFrom-Json
        foreach ($p in $parsed.packs) {
            $existing[$p.id] = $p
        }
    }
    foreach ($entry in $catalogPacks) {
        $existing[$entry.id] = $entry
    }
    $merged = [ordered]@{
        packs = @($OfficialPacks | ForEach-Object {
            if ($existing.ContainsKey($_)) { $existing[$_] } else { [ordered]@{ id = $_; size_bytes = 0; sha256 = "" } }
        })
    }
    ($merged | ConvertTo-Json -Depth 4) | Set-Content $catalogPath -Encoding UTF8
    Write-Host "updated catalog: $catalogPath"
}

Write-Host "pack-all done ($($targets.Count) requested, output: $OutDir)"
