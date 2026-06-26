param(
    [ValidateRange(1, 1000000)]
    [int]$Population = 20
)

$ErrorActionPreference = "Stop"

$repoRoot    = Split-Path -Parent $PSScriptRoot
$syntheaRoot = Join-Path $repoRoot "services\synthea"
$outputDir   = Join-Path $syntheaRoot "output\fhir"
$runner      = Join-Path $syntheaRoot "run_synthea.bat"

if (-not (Test-Path $runner)) {
    throw "No se encuentra run_synthea.bat en $syntheaRoot"
}

if (Test-Path $outputDir) {
    Get-ChildItem $outputDir -File -Filter *.json -ErrorAction SilentlyContinue | Remove-Item -Force
} else {
    New-Item -ItemType Directory -Path $outputDir | Out-Null
}

Push-Location $syntheaRoot
try {
    & .\run_synthea.bat -p $Population

    if ($LASTEXITCODE -ne 0) {
        throw "Synthea terminó con código de salida $LASTEXITCODE"
    }
}
finally {
    Pop-Location
}

$generatedFiles = Get-ChildItem $outputDir -File -Filter *.json -ErrorAction SilentlyContinue

if (-not $generatedFiles) {
    throw "La ejecución terminó, pero no se generaron archivos JSON en $outputDir"
}

Write-Host ""
Write-Host "Contenido generado en output\fhir:" -ForegroundColor Cyan
$generatedFiles | Select-Object Name, Length, LastWriteTime