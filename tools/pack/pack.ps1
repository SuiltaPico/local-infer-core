# Validate (and optionally zip) a manifest-driven model pack directory.
param(
    [Parameter(Mandatory = $true)]
    [string]$PackDir,
    [string]$OutZip = $null
)

$ErrorActionPreference = "Stop"
$PackDir = Resolve-Path $PackDir

$ManifestPath = Join-Path $PackDir "manifest.json"
if (-not (Test-Path $ManifestPath)) {
    Write-Error "missing manifest.json in $PackDir"
    exit 1
}

$Manifest = Get-Content $ManifestPath -Raw | ConvertFrom-Json
$PackId = $Manifest.id
if (-not $PackId) {
    Write-Error "manifest.id is empty"
    exit 1
}

$DirName = Split-Path $PackDir -Leaf
if ($DirName -ne $PackId) {
    Write-Error "directory name must match manifest.id: $DirName != $PackId"
    exit 1
}

if ($Manifest.schema -ne 1) {
    Write-Error "unsupported schema: $($Manifest.schema)"
    exit 1
}

if (-not $Manifest.license) {
    Write-Error "missing license section"
    exit 1
}

foreach ($rel in $Manifest.license.files) {
    $path = Join-Path $PackDir $rel
    if (-not (Test-Path $path)) {
        Write-Error "missing license file: $rel"
        exit 1
    }
    if ((Get-Item $path).Length -eq 0) {
        Write-Error "empty license file: $rel"
        exit 1
    }
}

foreach ($prop in $Manifest.files.PSObject.Properties) {
    $key = $prop.Name
    $name = $prop.Value
    $path = Join-Path $PackDir $name
    if (-not (Test-Path $path)) {
        Write-Error "missing weight file files.$key -> $name"
        exit 1
    }
}

Write-Host "pack OK: $PackId ($PackDir)"

if ($OutZip) {
    if (Test-Path $OutZip) { Remove-Item $OutZip -Force }
    Compress-Archive -Path (Join-Path $PackDir "*") -DestinationPath $OutZip -Force
    Write-Host "wrote zip: $OutZip"
}
