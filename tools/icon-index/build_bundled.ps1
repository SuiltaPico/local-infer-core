# Build icons.bundled.v1.mobileclip2-s0.* packs from PNG templates.
param(
    [ValidateSet("int8", "fp32", "all")]
    [string]$Quant = "all",

    [string]$AssetsDir = "",

    [switch]$SkipIconDownload
)

$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
if (-not $AssetsDir) {
    $AssetsDir = Join-Path $RepoRoot "assets"
}
$FixturesDir = Join-Path $RepoRoot "crates\infer-core\tests\fixtures"
$EmbedVision = Join-Path $FixturesDir "embed.mobileclip2-s0.onnx.fp32\vision.onnx"
$IconsPngDir = Join-Path $AssetsDir "icons"

function Get-InferCoreHelper {
    param([string]$RepoRoot)

    $exeName = if ($IsWindows -or ($env:OS -match "Windows")) { "infer-core-helper.exe" } else { "infer-core-helper" }
    return Join-Path $RepoRoot (Join-Path "target" (Join-Path "release" $exeName))
}

function Test-IconsBundledLayout {
    param([string]$IconsDir)
    $required = @("mdi", "fluent", "tabler", "fa")
    $total = 0
    foreach ($ns in $required) {
        $subdir = Join-Path $IconsDir $ns
        if (-not (Test-Path $subdir)) { return $false }
        $n = (Get-ChildItem $subdir -Filter *.png -ErrorAction SilentlyContinue).Count
        if ($n -eq 0) { return $false }
        $total += $n
    }
    # MDI ~7k + Tabler ~5k + Fluent ~3k + FA ~3k — expect well over 10k when complete.
    return ($total -ge 15000)
}

function Ensure-IconPngs {
    param([string]$IconsDir)
    if ((Test-Path $IconsDir) -and (Test-IconsBundledLayout $IconsDir)) {
        $count = (Get-ChildItem $IconsDir -Recurse -Filter *.png -ErrorAction SilentlyContinue).Count
        Write-Host "icon PNG templates ready ($count files, all namespaces under $IconsDir)"
        return
    }
    $partial = if (Test-Path $IconsDir) {
        (Get-ChildItem $IconsDir -Recurse -Filter *.png -ErrorAction SilentlyContinue).Count
    } else { 0 }
    if ($partial -gt 0) {
        Write-Host "incomplete icon layout ($partial PNGs) — re-downloading MDI / Tabler / Fluent / FA ..."
    }
    if ($SkipIconDownload) {
        throw "icon PNGs incomplete under $IconsDir — run scripts/download_icons.ps1 -Rasterize or omit -SkipIconDownload"
    }
    Write-Host "downloading and rasterizing icon libraries (MDI / Tabler / Fluent / FA)..."
    & (Join-Path $RepoRoot "scripts\download_icons.ps1") -OutDir $AssetsDir -Rasterize
    if ($LASTEXITCODE -gt 0) { exit $LASTEXITCODE }
    if (-not (Test-IconsBundledLayout $IconsDir)) {
        throw "icon download finished but layout still incomplete — check scripts/download_icons.ps1 output"
    }
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
    $embedModelId = "embed.mobileclip2-s0.onnx.fp32"

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

function Prepare-IconsPackDir {
    param(
        [ValidateSet("int8", "fp32")][string]$Quant
    )

    $PackId = "icons.bundled.v1.mobileclip2-s0.$Quant"
    $PackDir = Join-Path $FixturesDir $PackId
    New-Item -ItemType Directory -Force -Path $PackDir | Out-Null
    $shared = Join-Path $RepoRoot "packs\shared\icons"
    Copy-Item (Join-Path $shared "LICENSE") (Join-Path $PackDir "LICENSE") -Force
    Copy-Item (Join-Path $shared "NOTICE") (Join-Path $PackDir "NOTICE") -Force
    return @{
        PackId   = $PackId
        PackDir  = $PackDir
        OutIndex = Join-Path $PackDir "embeddings.bin"
    }
}

function Write-IconsPackManifest {
    param(
        [hashtable]$Pack,
        [int]$Count,
        [string[]]$Namespaces
    )

    $Quant = if ($Pack.PackId -match '\.fp32$') { "fp32" } else { "int8" }
    Write-IconsBundledManifest -PackDir $Pack.PackDir -PackId $Pack.PackId -Quant $Quant -Count $Count -Namespaces $Namespaces
    Write-Host "pack ready: $($Pack.PackDir) ($($Pack.PackId), $Count icons)"
}

function Build-IconsPacks {
    param(
        [string[]]$Targets
    )

    $int8Pack = $null
    $fp32Pack = $null
    foreach ($q in $Targets) {
        $pack = Prepare-IconsPackDir -Quant $q
        if ($q -eq "int8") { $int8Pack = $pack } else { $fp32Pack = $pack }
    }

    Write-Host "building icons.bundled ($($Targets -join ', ')) ..."
    Push-Location $RepoRoot
    try {
        cargo build -p infer-core --release --bin infer-core-helper
        if ($LASTEXITCODE -gt 0) { exit $LASTEXITCODE }

        $bin = Get-InferCoreHelper -RepoRoot $RepoRoot
        $buildArgs = @(
            "icon", "index-build",
            "--png-dir", $IconsPngDir,
            "--vision-model", $EmbedVision
        )
        if ($int8Pack) { $buildArgs += @("--out-int8", $int8Pack.OutIndex) }
        if ($fp32Pack) { $buildArgs += @("--out-fp32", $fp32Pack.OutIndex) }
        & $bin @buildArgs
        if ($LASTEXITCODE -gt 0) { throw "infer-core-helper icon index-build failed" }
    }
    finally {
        Pop-Location
    }

    foreach ($pack in @($int8Pack, $fp32Pack)) {
        if (-not $pack) { continue }
        if (-not (Test-Path $pack.OutIndex)) {
            throw "embeddings.bin not produced at $($pack.OutIndex)"
        }
    }

    $namespaces = Get-IconNamespaces -IconsDir $IconsPngDir
    $pngCount = if ($namespaces.Count -gt 0) {
        ($namespaces | ForEach-Object {
            (Get-ChildItem (Join-Path $IconsPngDir $_) -Filter *.png -ErrorAction SilentlyContinue).Count
        } | Measure-Object -Sum).Sum
    } else {
        (Get-ChildItem $IconsPngDir -Filter *.png -ErrorAction SilentlyContinue).Count
    }

    foreach ($pack in @($int8Pack, $fp32Pack)) {
        if (-not $pack) { continue }
        Write-Host "writing manifest for $($pack.PackId) ..."
        Write-IconsPackManifest -Pack $pack -Count $pngCount -Namespaces $namespaces
    }
}

if (-not (Test-Path $EmbedVision)) {
    Write-Host "embed vision model missing — downloading embed.mobileclip2-s0.onnx.fp32"
    & (Join-Path $RepoRoot "scripts\download_embed_mobileclip2_pack.ps1") -Quant fp32
}

Ensure-IconPngs -IconsDir $IconsPngDir

$targets = if ($Quant -eq "all") { @("int8", "fp32") } else { @($Quant) }
Build-IconsPacks -Targets $targets

Write-Host "icons.bundled packs ready under $FixturesDir"
