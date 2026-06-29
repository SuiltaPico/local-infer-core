# Shared ONNX -> MNN conversion helpers (requires pip install MNN in repo .env or mnnconvert on PATH).

function Resolve-MnnConvert {
    $RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $Candidates = @(
        (Join-Path $RepoRoot ".env\Scripts\mnnconvert.exe"),
        (Join-Path $RepoRoot ".venv\Scripts\mnnconvert.exe")
    )
    foreach ($path in $Candidates) {
        if (Test-Path $path) { return $path }
    }
    $onPath = Get-Command mnnconvert -ErrorAction SilentlyContinue
    if ($onPath) { return $onPath.Source }
    throw "mnnconvert not found — run: pip install -U MNN (repo .env recommended)"
}

function Convert-OnnxToMnn {
    param(
        [Parameter(Mandatory)][string]$OnnxPath,
        [Parameter(Mandatory)][string]$MnnPath,
        [int]$WeightQuantBits = 0,
        [switch]$Force
    )

    if (-not (Test-Path $OnnxPath)) {
        throw "missing ONNX source: $OnnxPath"
    }

    $MnnDir = Split-Path $MnnPath -Parent
    if ($MnnDir -and -not (Test-Path $MnnDir)) {
        New-Item -ItemType Directory -Force -Path $MnnDir | Out-Null
    }

    if ((Test-Path $MnnPath) -and -not $Force) {
        Write-Host "  skip (exists): $(Split-Path $MnnPath -Leaf)"
        return
    }

    $MnnConvert = Resolve-MnnConvert
    $args = @(
        "-f", "ONNX",
        "--modelFile", $OnnxPath,
        "--MNNModel", $MnnPath,
        "--bizCode", "local-infer-core"
    )
    if ($WeightQuantBits -gt 0) {
        $args += @("--weightQuantBits", "$WeightQuantBits")
    }
    # CI runners have ~14 GB RAM; limit converter threads to reduce peak working set.
    if ($env:CI -eq "true") {
        $args += @("--threadNum", "1")
    }

    Write-Host "  converting: $(Split-Path $OnnxPath -Leaf) -> $(Split-Path $MnnPath -Leaf)"
    # Run each convert in a fresh process so native heap is fully released between det/rec.
    $proc = Start-Process -FilePath $MnnConvert -ArgumentList $args -Wait -PassThru -NoNewWindow
    $exitCode = $proc.ExitCode

    # mnnconvert on Windows may crash during telemetry cleanup after a successful convert (exit 0xC0000005).
    if (-not (Test-Path $MnnPath) -or (Get-Item $MnnPath).Length -eq 0) {
        throw "mnnconvert failed for $OnnxPath (exit $exitCode, no output at $MnnPath)"
    }
    if ($exitCode -ne 0) {
        Write-Warning "mnnconvert exited $exitCode but output exists — treating as success"
    }
    # Native exit code survives past Write-Host; reset so parent scripts don't fail CI.
    $global:LASTEXITCODE = 0
}
