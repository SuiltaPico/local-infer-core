# Build icons.bundled.v1.mobileclip2-s0.* packs from PNG templates.
param(
    [ValidateSet("int8", "fp32", "all")]
    [string]$Quant = "all",

    [string]$UiExtractorRoot = (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) "..\ui-extractor"),

    [switch]$SkipIconDownload
)

$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$FixturesDir = Join-Path $RepoRoot "crates\infer-core\tests\fixtures"
$EmbedVision = Join-Path $FixturesDir "embed.mobileclip2-s0.onnx.fp32\vision.onnx"
$IconsPngDir = Join-Path $UiExtractorRoot "assets\icons"

function Resolve-UiExtractorRoot {
    param([string]$Candidate)
    $resolved = Resolve-Path $Candidate -ErrorAction SilentlyContinue
    if ($resolved) { return $resolved.Path }
    throw "ui-extractor not found at $Candidate — pass -UiExtractorRoot"
}

function Ensure-IconPngs {
    param([string]$Root, [string]$IconsDir)
    $count = 0
    if (Test-Path $IconsDir) {
        $count = (Get-ChildItem $IconsDir -Recurse -Filter *.png -ErrorAction SilentlyContinue).Count
    }
    if ($count -gt 0) {
        Write-Host "icon PNG templates ready ($count files under $IconsDir)"
        return
    }
    if ($SkipIconDownload) {
        throw "no PNG icons under $IconsDir — run ui-extractor scripts/download_icons.ps1 -Rasterize or omit -SkipIconDownload"
    }
    Write-Host "downloading and rasterizing icon libraries (MDI / Tabler / Fluent / FA)..."
    & (Join-Path $Root "scripts\download_icons.ps1") -Rasterize
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

function Get-IconNamespaces {
    param([string]$IconsDir)
    if (-not (Test-Path $IconsDir)) { return @() }
    return Get-ChildItem $IconsDir -Directory |
        Where-Object { (Get-ChildItem $_.FullName -Filter *.png -ErrorAction SilentlyContinue).Count -gt 0 } |
        ForEach-Object { $_.Name } |
        Sort-Object
}

function Write-IconsBundledManifest {
    param(
        [string]$PackDir,
        [string]$PackId,
        [string]$Quant,
        [int]$Count,
        [string[]]$Namespaces
    )

    $indexFormat = if ($Quant -eq "fp32") { "mcl2-v1" } else { "mcl2-v2" }
    $embedModelId = "embed.mobileclip2-s0.onnx.$Quant"

    $upstream = @(
        [ordered]@{ name = "Material Design Icons"; spdx = "Apache-2.0"; url = "https://github.com/Templarian/MaterialDesign-SVG" },
        [ordered]@{ name = "Tabler Icons"; spdx = "MIT"; url = "https://github.com/tabler/tabler-icons" },
        [ordered]@{ name = "Fluent UI System Icons"; spdx = "MIT"; url = "https://github.com/microsoft/fluentui-system-icons" },
        [ordered]@{ name = "Font Awesome Free"; spdx = "SEE NOTICE"; url = "https://fontawesome.com/license/free" }
    )

    $manifest = [ordered]@{
        schema         = 1
        id             = $PackId
        kind           = "icon_index"
        embed_model_id = $embedModelId
        files          = [ordered]@{ index = "embeddings.bin" }
        namespaces     = @($Namespaces)
        count          = $Count
        index_format   = $indexFormat
        license        = [ordered]@{
            spdx     = "SEE NOTICE"
            files    = @("LICENSE", "NOTICE")
            upstream = $upstream
        }
    }

    ($manifest | ConvertTo-Json -Depth 6) | Set-Content (Join-Path $PackDir "manifest.json") -Encoding UTF8
}

function Build-IconsPack {
    param(
        [ValidateSet("int8", "fp32")][string]$Quant
    )

    $PackId = "icons.bundled.v1.mobileclip2-s0.$Quant"
    $PackDir = Join-Path $FixturesDir $PackId
    $OutIndex = Join-Path $PackDir "embeddings.bin"
    $FormatArg = if ($Quant -eq "fp32") { "f32" } else { "int8" }

    New-Item -ItemType Directory -Force -Path $PackDir | Out-Null
    $shared = Join-Path $RepoRoot "packs\shared\icons"
    Copy-Item (Join-Path $shared "LICENSE") (Join-Path $PackDir "LICENSE") -Force
    Copy-Item (Join-Path $shared "NOTICE") (Join-Path $PackDir "NOTICE") -Force

    Write-Host "building $PackId ..."
    Push-Location $RepoRoot
    try {
        cargo build -p infer-core --release --bin icon-index-build
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

        $bin = Join-Path $RepoRoot "target\release\icon-index-build.exe"
        & $bin `
            --png-dir $IconsPngDir `
            --vision-model $EmbedVision `
            --out $OutIndex `
            --format $FormatArg
        if ($? -ne $true) { throw "icon-index-build failed for $PackId" }
    }
    finally {
        Pop-Location
    }

    if (-not (Test-Path $OutIndex)) {
        throw "embeddings.bin not produced at $OutIndex"
    }

    Write-Host "writing manifest for $PackId ..."
    $namespaces = Get-IconNamespaces -IconsDir $IconsPngDir
    # Re-counting 7k+ PNGs is slow; icon-index-build already validated the set.
    $pngCount = if ($namespaces.Count -gt 0) {
        ($namespaces | ForEach-Object {
            (Get-ChildItem (Join-Path $IconsPngDir $_) -Filter *.png -ErrorAction SilentlyContinue).Count
        } | Measure-Object -Sum).Sum
    } else {
        (Get-ChildItem $IconsPngDir -Filter *.png -ErrorAction SilentlyContinue).Count
    }
    Write-IconsBundledManifest -PackDir $PackDir -PackId $PackId -Quant $Quant -Count $pngCount -Namespaces $namespaces
    Write-Host "pack ready: $PackDir ($PackId, $pngCount icons)"
}

$UiExtractorRoot = Resolve-UiExtractorRoot $UiExtractorRoot

if (-not (Test-Path $EmbedVision)) {
    Write-Host "embed vision model missing — downloading embed.mobileclip2-s0.onnx.fp32"
    & (Join-Path $RepoRoot "scripts\download_embed_mobileclip2_pack.ps1") -Quant fp32
}

Ensure-IconPngs -Root $UiExtractorRoot -IconsDir $IconsPngDir

$targets = if ($Quant -eq "all") { @("int8", "fp32") } else { @($Quant) }
foreach ($q in $targets) {
    Build-IconsPack -Quant $q
}

Write-Host "icons.bundled packs ready under $FixturesDir"
