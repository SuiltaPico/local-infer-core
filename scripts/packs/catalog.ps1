# Shared model pack catalog + GitHub Release URL helpers (local-infer-core).
$script:DefaultReleaseRepo = "SuiltaPico/local-infer-core"
$script:DefaultReleaseTag = "v0.1.0"

function Get-InferCoreRepoRoot {
    $here = $PSScriptRoot
    if (-not $here) { $here = Split-Path -Parent $MyInvocation.MyCommand.Path }
    return (Split-Path (Split-Path $here -Parent) -Parent)
}

function Resolve-PackCatalogPath {
    param([string]$ExplicitPath = "")

    if ($ExplicitPath -and (Test-Path $ExplicitPath)) {
        return (Resolve-Path $ExplicitPath).Path
    }

    $repoRoot = Get-InferCoreRepoRoot
    $candidate = Join-Path $repoRoot "dart\assets\catalog.json"
    if (Test-Path $candidate) { return $candidate }

    $sibling = Join-Path (Split-Path $repoRoot -Parent) "local-infer-core\dart\assets\catalog.json"
    if (Test-Path $sibling) { return $sibling }

    return $null
}

function Read-PackCatalog {
    param([string]$CatalogPath = "")

    $path = Resolve-PackCatalogPath -ExplicitPath $CatalogPath
    if (-not $path) {
        return [ordered]@{
            release = [ordered]@{
                repo = $script:DefaultReleaseRepo
                tag  = $script:DefaultReleaseTag
            }
            packs   = @()
        }
    }

    $raw = Get-Content $path -Raw | ConvertFrom-Json
    $release = if ($raw.release) {
        [ordered]@{
            repo = if ($raw.release.repo) { [string]$raw.release.repo } else { $script:DefaultReleaseRepo }
            tag  = if ($raw.release.tag) { [string]$raw.release.tag } else { $script:DefaultReleaseTag }
        }
    } else {
        [ordered]@{
            repo = $script:DefaultReleaseRepo
            tag  = $script:DefaultReleaseTag
        }
    }

    return [ordered]@{
        release = $release
        packs   = @($raw.packs)
    }
}

function Get-ReleaseTag {
    param([string]$Tag = "")

    if ($Tag) { return $(if ($Tag -match '^v') { $Tag } else { "v$Tag" }) }
    $envTag = $env:LOCAL_INFER_RELEASE_TAG
    if ($envTag) { return $(if ($envTag -match '^v') { $envTag } else { "v$envTag" }) }
    $catalog = Read-PackCatalog
    return $catalog.release.tag
}

function Get-ReleaseRepo {
    param([string]$Repo = "")

    if ($Repo) { return $Repo }
    $envRepo = $env:LOCAL_INFER_RELEASE_REPO
    if ($envRepo) { return $envRepo }
    $catalog = Read-PackCatalog
    return $catalog.release.repo
}

function Get-PackReleaseUrl {
    param(
        [Parameter(Mandatory)][string]$PackId,
        [string]$Repo = "",
        [string]$Tag = ""
    )

    $repo = Get-ReleaseRepo -Repo $Repo
    $vTag = Get-ReleaseTag -Tag $Tag
    return "https://github.com/$repo/releases/download/$vTag/$PackId.zip"
}

function Get-CatalogPackEntry {
    param(
        [Parameter(Mandatory)][string]$PackId,
        [string]$CatalogPath = ""
    )

    $catalog = Read-PackCatalog -CatalogPath $CatalogPath
    foreach ($entry in $catalog.packs) {
        if ([string]$entry.id -eq $PackId) {
            return $entry
        }
    }
    return $null
}

function Get-PackDownloadUrl {
    param(
        [Parameter(Mandatory)][string]$PackId,
        [string]$Repo = "",
        [string]$Tag = "",
        [string]$CatalogPath = ""
    )

    $entry = Get-CatalogPackEntry -PackId $PackId -CatalogPath $CatalogPath
    if ($entry -and $entry.urls -and $entry.urls.Count -gt 0) {
        return [string]$entry.urls[0]
    }
    return (Get-PackReleaseUrl -PackId $PackId -Repo $Repo -Tag $Tag)
}

function Test-PackInstalled {
    param(
        [Parameter(Mandatory)][string]$ModelsRoot,
        [Parameter(Mandatory)][string]$PackId
    )

    return Test-Path (Join-Path (Join-Path $ModelsRoot $PackId) "manifest.json")
}

function Expand-PackZipFile {
    param(
        [Parameter(Mandatory)][string]$ZipPath,
        [Parameter(Mandatory)][string]$PackId,
        [Parameter(Mandatory)][string]$DestRoot,
        [switch]$Force
    )

    if (-not (Test-Path $ZipPath)) {
        throw "Pack zip not found: $ZipPath"
    }

    $dest = Join-Path $DestRoot $PackId
    if ((Test-Path $dest) -and -not $Force) {
        if (Test-Path (Join-Path $dest "manifest.json")) {
            return $dest
        }
    }

    if (Test-Path $dest) { Remove-Item -Recurse -Force $dest }
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    Expand-Archive -Path $ZipPath -DestinationPath $dest -Force

    $manifest = Join-Path $dest "manifest.json"
    if (-not (Test-Path $manifest)) {
        throw "Invalid pack zip (missing manifest.json): $ZipPath"
    }

    $id = (Get-Content $manifest -Raw | ConvertFrom-Json).id
    if ($id -ne $PackId) {
        throw "manifest.id mismatch in ${ZipPath}: expected $PackId, got $id"
    }

    return $dest
}

function Install-PackFromDirectory {
    param(
        [Parameter(Mandatory)][string]$SourceDir,
        [Parameter(Mandatory)][string]$PackId,
        [Parameter(Mandatory)][string]$DestRoot,
        [switch]$Force
    )

    if (-not (Test-Path (Join-Path $SourceDir "manifest.json"))) {
        throw "Source pack dir missing manifest.json: $SourceDir"
    }

    $dest = Join-Path $DestRoot $PackId
    if ((Test-Path $dest) -and -not $Force) {
        if (Test-Path (Join-Path $dest "manifest.json")) {
            return $dest
        }
    }

    if (Test-Path $dest) { Remove-Item -Recurse -Force $dest }
    Copy-Item -Path $SourceDir -Destination $dest -Recurse -Force

    $id = (Get-Content (Join-Path $dest "manifest.json") -Raw | ConvertFrom-Json).id
    if ($id -ne $PackId) {
        throw "manifest.id mismatch in ${SourceDir}: expected $PackId, got $id"
    }

    return $dest
}

function Download-PackZip {
    param(
        [Parameter(Mandatory)][string]$Url,
        [Parameter(Mandatory)][string]$DestPath,
        [string]$ExpectedSha256 = ""
    )

    $parent = Split-Path $DestPath -Parent
    if ($parent -and -not (Test-Path $parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }

    Write-Host "downloading: $Url"
    Invoke-WebRequest -Uri $Url -OutFile $DestPath -UseBasicParsing

    if ($ExpectedSha256 -and $ExpectedSha256.Trim()) {
        $hash = (Get-FileHash -Path $DestPath -Algorithm SHA256).Hash.ToLowerInvariant()
        $expected = $ExpectedSha256.Trim().ToLowerInvariant()
        if ($hash -ne $expected) {
            Remove-Item -Force $DestPath -ErrorAction SilentlyContinue
            throw "sha256 mismatch for $Url`: expected $expected, got $hash"
        }
    }

    return $DestPath
}
