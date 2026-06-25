# Package infer-core native libraries for GitHub Releases.
param(
    [string]$OutDir = "dist",
    [switch]$SkipPack
)
$ErrorActionPreference = "Stop"

$Root = Split-Path $PSScriptRoot -Parent
Push-Location $Root
try {
    $windowsTargets = @(
        @{ Triple = "x86_64-pc-windows-msvc"; Label = "windows-x86_64" },
        @{ Triple = "aarch64-pc-windows-msvc"; Label = "windows-aarch64" }
    )

    $prevEap = $ErrorActionPreference
    foreach ($t in $windowsTargets) {
        Write-Host "Building $($t.Label) ($($t.Triple))..."
        $ErrorActionPreference = 'SilentlyContinue'
        rustup target add $t.Triple 2>&1 | Out-Null
        $ErrorActionPreference = $prevEap
        cargo build -p infer-core-ffi --release --target $t.Triple
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    }

    if ($SkipPack) {
        Write-Host "SkipPack set; binaries left under target/<triple>/release/"
        return
    }

    New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

    foreach ($t in $windowsTargets) {
        $dll = Join-Path $Root "target\$($t.Triple)\release\infer_core.dll"
        if (-not (Test-Path $dll)) { throw "Build output not found: $dll" }

        $stage = Join-Path $OutDir "infer-core-$($t.Label)"
        New-Item -ItemType Directory -Force -Path "$stage/lib" | Out-Null
        Copy-Item $dll "$stage/lib/infer_core.dll"
        $zip = Join-Path $OutDir "infer-core-$($t.Label).zip"
        if (Test-Path $zip) { Remove-Item -Force $zip }
        Compress-Archive -Path "$stage/*" -DestinationPath $zip -Force
        Remove-Item -Recurse -Force $stage
        Write-Host "Packaged: $zip"
    }
} finally {
    Pop-Location
}
