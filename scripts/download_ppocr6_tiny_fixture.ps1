# Download PP-OCRv6 tiny ONNX weights into the infer-core test fixture pack.
# Also fetches a PaddleOCR sample image for integration tests.
$ErrorActionPreference = "Stop"

& "$PSScriptRoot\download_ppocr6_pack.ps1" -Size tiny -Quant fp32 @args
