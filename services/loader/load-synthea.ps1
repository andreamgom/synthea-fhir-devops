param(
    [string]$FhirBaseUrl = "http://localhost:8080/fhir/",
    [string]$InputPath = "C:\dev\synthea-fhir-devops\services\synthea\output\fhir"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $InputPath)) {
    throw "No existe la carpeta de entrada: $InputPath"
}

$hospitalBundle = Get-ChildItem $InputPath -Filter "hospitalInformation*.json" | Select-Object -First 1
$practitionerBundle = Get-ChildItem $InputPath -Filter "practitionerInformation*.json" | Select-Object -First 1
$patientBundles = Get-ChildItem $InputPath -Filter "*.json" | Where-Object {
    $_.Name -notlike "hospitalInformation*.json" -and $_.Name -notlike "practitionerInformation*.json"
}

if (-not $hospitalBundle) {
    throw "No se encontró hospitalInformation*.json"
}

if (-not $practitionerBundle) {
    throw "No se encontró practitionerInformation*.json"
}

Invoke-RestMethod -Uri $FhirBaseUrl -Method Post -ContentType "application/fhir+json" -InFile $hospitalBundle.FullName | Out-Null
Invoke-RestMethod -Uri $FhirBaseUrl -Method Post -ContentType "application/fhir+json" -InFile $practitionerBundle.FullName | Out-Null

foreach ($bundle in $patientBundles) {
    Invoke-RestMethod -Uri $FhirBaseUrl -Method Post -ContentType "application/fhir+json" -InFile $bundle.FullName | Out-Null
}

[pscustomobject]@{
    PatientTotal     = (Invoke-RestMethod "${FhirBaseUrl}Patient?_summary=count").total
    ConditionTotal   = (Invoke-RestMethod "${FhirBaseUrl}Condition?_summary=count").total
    ProcedureTotal   = (Invoke-RestMethod "${FhirBaseUrl}Procedure?_summary=count").total
    ObservationTotal = (Invoke-RestMethod "${FhirBaseUrl}Observation?_summary=count").total
}