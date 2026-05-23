param(
    [int]$Population = 5
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$syntheaRoot = $scriptDir
$outputDir = Join-Path $syntheaRoot "output\fhir"

if (-not (Test-Path (Join-Path $syntheaRoot "run_synthea.bat"))) {
    throw "No se encuentra run_synthea.bat en $syntheaRoot"
}

if (Test-Path $outputDir) {
    Get-ChildItem $outputDir -File -ErrorAction SilentlyContinue | Remove-Item -Force
} else {
    New-Item -ItemType Directory -Path $outputDir | Out-Null
}

Push-Location $syntheaRoot
try {
    .\run_synthea.bat -p $Population
}
finally {
    Pop-Location
}

Get-ChildItem $outputDir