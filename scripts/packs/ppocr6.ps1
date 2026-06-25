# PP-OCRv6 pack metadata shared by download scripts.
$script:Ppocr6BaseUrl = "https://paddle-model-ecology.bj.bcebos.com/paddlex/official_inference_model/paddle3.0.0"
$script:ModelScopeDictBase = "https://www.modelscope.cn/api/v1/models/greatv/oar-ocr/repo?Revision=master&FilePath="

$script:Ppocr6Sizes = @{
    tiny   = @{ DictFile = "ppocrv6_tiny_dict.txt" }
    small  = @{ DictFile = "ppocrv6_dict.txt" }
    medium = @{ DictFile = "ppocrv6_dict.txt" }
}

function Get-Ppocr6PackId {
    param(
        [Parameter(Mandatory)][ValidateSet("tiny", "small", "medium")][string]$Size,
        [Parameter(Mandatory)][ValidateSet("int8", "fp32")][string]$Quant,
        [ValidateSet("onnx", "mnn")][string]$Format = "onnx"
    )
    return "ocr.paddle.ppocr6-$Size.$Format.$Quant"
}

function Get-Ppocr6DetTarName {
    param([Parameter(Mandatory)][string]$Size)
    return "PP-OCRv6_${Size}_det_onnx_infer.tar"
}

function Get-Ppocr6RecTarName {
    param([Parameter(Mandatory)][string]$Size)
    return "PP-OCRv6_${Size}_rec_onnx_infer.tar"
}

function Get-Ppocr6DictUrl {
    param([Parameter(Mandatory)][string]$DictFile)
    return "$script:ModelScopeDictBase$DictFile"
}

function Write-Ppocr6Manifest {
    param(
        [Parameter(Mandatory)][string]$PackDir,
        [Parameter(Mandatory)][string]$PackId,
        [Parameter(Mandatory)][string]$Size,
        [Parameter(Mandatory)][string]$Quant,
        [Parameter(Mandatory)][string]$DictFile,
        [ValidateSet("onnx", "mnn")][string]$Format = "onnx"
    )

    $versionLabel = switch ($Size) {
        "tiny" { "PP-OCRv6_tiny" }
        "small" { "PP-OCRv6_small" }
        "medium" { "PP-OCRv6_medium" }
    }

    $weightExt = if ($Format -eq "mnn") { "mnn" } else { "onnx" }
    $runtime = if ($Format -eq "mnn") { "mnn" } else { "onnxruntime" }

    $manifest = [ordered]@{
        schema    = 1
        id        = $PackId
        kind      = "ocr"
        family    = "paddle"
        version   = 6
        format    = $Format
        quant     = $Quant
        files     = [ordered]@{
            det  = "det.$weightExt"
            rec  = "rec.$weightExt"
            dict = $DictFile
        }
        runtime   = $runtime
        inputs    = [ordered]@{ det_max_side = 960; rec_height = 48 }
        detection = [ordered]@{
            score_threshold = 0.2
            box_threshold   = 0.45
            unclip_ratio    = 1.4
        }
        license   = [ordered]@{
            spdx     = "Apache-2.0"
            files    = @("LICENSE", "NOTICE")
            upstream = [ordered]@{
                name    = "PaddleOCR / PP-OCRv6"
                url     = "https://github.com/PaddlePaddle/PaddleOCR"
                version = $versionLabel
            }
        }
    }

    if ($Quant -eq "int8") {
        $manifest.runtime_hint = [ordered]@{
            ep     = @("cpu")
            reason = "tiny model, cpu_ok"
        }
    }

    $json = $manifest | ConvertTo-Json -Depth 6
    Set-Content -Path (Join-Path $PackDir "manifest.json") -Value $json -Encoding UTF8
}

function Copy-Ppocr6LicenseFiles {
    param([Parameter(Mandatory)][string]$PackDir)
    $repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $shared = Join-Path $repoRoot "packs\shared\ocr"
    Copy-Item (Join-Path $shared "LICENSE") (Join-Path $PackDir "LICENSE") -Force
    Copy-Item (Join-Path $shared "NOTICE") (Join-Path $PackDir "NOTICE") -Force
}

function Extract-Ppocr6OnnxFromTar {
    param(
        [Parameter(Mandatory)][string]$TarUrl,
        [Parameter(Mandatory)][string]$DestOnnx
    )
    if (Test-Path $DestOnnx) {
        Write-Host "  skip (exists): $(Split-Path $DestOnnx -Leaf)"
        return
    }

    $Tmp = Join-Path $env:TEMP ("ppocr6-" + [guid]::NewGuid().ToString())
    New-Item -ItemType Directory -Force -Path $Tmp | Out-Null
    try {
        $TarFile = Join-Path $Tmp "model.tar"
        Write-Host "  downloading: $TarUrl"
        Invoke-WebRequest -Uri $TarUrl -OutFile $TarFile
        tar -xf $TarFile -C $Tmp
        $Onnx = Get-ChildItem -Path $Tmp -Recurse -Filter "*.onnx" | Select-Object -First 1
        if (-not $Onnx) { throw "no .onnx in $TarUrl" }
        Copy-Item $Onnx.FullName $DestOnnx -Force
        Write-Host "  -> $(Split-Path $DestOnnx -Leaf)"
    }
    finally {
        Remove-Item -Recurse -Force $Tmp -ErrorAction SilentlyContinue
    }
}

function Ensure-Ppocr6SampleImage {
    param([Parameter(Mandatory)][string]$FixturesDir)
    $SampleDest = Join-Path $FixturesDir "sample_ocr.jpg"
    if (Test-Path $SampleDest) { return }
    $SampleImg = "https://raw.githubusercontent.com/PaddlePaddle/PaddleOCR/release/2.7/doc/imgs/11.jpg"
    Write-Host "downloading sample image: $SampleImg"
    Invoke-WebRequest -Uri $SampleImg -OutFile $SampleDest
}
