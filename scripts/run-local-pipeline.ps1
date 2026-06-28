param(
    [int]$Population = 5,
    [string]$FhirBaseUrl = "http://localhost:8080/fhir/"
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$generateScript = Join-Path $repoRoot "scripts\generate-synthea.ps1"
$loadScript = Join-Path $repoRoot "services\loader\load-synthea.ps1"
$inputPath = Join-Path $repoRoot "services\synthea\output\fhir"

& $generateScript -Population $Population
& $loadScript -FhirBaseUrl $FhirBaseUrl -InputPath $inputPath