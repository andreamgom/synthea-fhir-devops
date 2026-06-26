# validate-neurorehab.ps1 - Versión corregida con códigos LOINC alineados al módulo
param(
    [int]$Population = 5
)

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "VALIDACION MODULO NEUROREHABILITACION" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""

# --- 1. Generar pacientes ---
Write-Host "[1/5] Generando $Population pacientes..." -ForegroundColor Cyan
Set-Location C:\dev\synthea-fhir-devops
.\scripts\generate-synthea.ps1 -Population $Population
Write-Host "OK Generacion completada" -ForegroundColor Green
Write-Host ""

# --- 2. Cargar bundles ---
Write-Host "[2/5] Analizando bundles FHIR..." -ForegroundColor Cyan
Set-Location C:\dev\synthea-fhir-devops\services\synthea\output\fhir

$bundles = Get-ChildItem -Filter "*.json" |
    Where-Object { $_.Name -notmatch "hospital|practitioner" }

if (-not $bundles) {
    Write-Host "ERROR: No se encontraron bundles de pacientes." -ForegroundColor Red
    exit 1
}

$totalObs  = 0; $totalProc = 0; $totalCond = 0; $totalMed = 0

foreach ($file in $bundles) {
    $b = Get-Content $file.FullName -Raw | ConvertFrom-Json
    $totalObs  += ($b.entry | Where-Object { $_.resource.resourceType -eq "Observation" }).Count
    $totalProc += ($b.entry | Where-Object { $_.resource.resourceType -eq "Procedure" }).Count
    $totalCond += ($b.entry | Where-Object { $_.resource.resourceType -eq "Condition" }).Count
    $totalMed  += ($b.entry | Where-Object { $_.resource.resourceType -eq "MedicationRequest" }).Count
}

Write-Host "  Pacientes:       $($bundles.Count)" -ForegroundColor White
Write-Host "  Observations:    $totalObs" -ForegroundColor White
Write-Host "  Procedures:      $totalProc" -ForegroundColor White
Write-Host "  Conditions:      $totalCond" -ForegroundColor White
Write-Host "  MedicationReqs:  $totalMed" -ForegroundColor White
Write-Host ""

# --- 3. Verificar escalas clínicas (códigos LOINC alineados al módulo) ---
Write-Host "[3/5] Verificando escalas clinicas por codigo LOINC..." -ForegroundColor Cyan

# IMPORTANTE: estos códigos deben coincidir exactamente con los del módulo neurorehab.json
$scales = @(
    @{ Code = "96761-3";  Name = "Barthel index" },
    @{ Code = "72133-2";  Name = "Berg Balance Scale" },
    @{ Code = "89386-5";  Name = "FAC (Functional Ambulation Categories)" },
    @{ Code = "72102-7";  Name = "PASS (Postural Assessment Scale)" },
    @{ Code = "75304-5";  Name = "FOIS (Functional Oral Intake Scale)" },
    @{ Code = "72106-8";  Name = "ACE-II (Addenbrooke Cognitive Examination)" },
    @{ Code = "83243-2";  Name = "FIM (Functional Independence Measure)" },
    @{ Code = "72105-0";  Name = "Fugl-Meyer Assessment" },
    @{ Code = "72007-8";  Name = "EuroQol VAS" },
    @{ Code = "39156-5";  Name = "IMC (Body Mass Index)" }
)

$scaleOK = 0
foreach ($scale in $scales) {
    $found = Select-String -Path "*.json" -Pattern $scale.Code -Quiet
    if ($found) {
        Write-Host "  OK $($scale.Name) [$($scale.Code)]" -ForegroundColor Green
        $scaleOK++
    } else {
        Write-Host "  FALTA $($scale.Name) [$($scale.Code)]" -ForegroundColor Red
    }
}
Write-Host ""

# --- 4. Verificar procedimientos de terapia ---
Write-Host "[4/5] Verificando procedimientos de terapia..." -ForegroundColor Cyan

$procedures = @(
    @{ Code = "36989003";  Name = "Fisioterapia (Physiotherapy)" },
    @{ Code = "386053000"; Name = "Logopedia (Speech and language therapy)" },
    @{ Code = "410155007"; Name = "Neuropsicologia (Neuropsychological assessment)" },
    @{ Code = "84478008";  Name = "Terapia Ocupacional (Occupational therapy)" }
)

$procOK = 0
foreach ($proc in $procedures) {
    $found = Select-String -Path "*.json" -Pattern $proc.Code -Quiet
    if ($found) {
        Write-Host "  OK $($proc.Name) [$($proc.Code)]" -ForegroundColor Green
        $procOK++
    } else {
        Write-Host "  FALTA $($proc.Name) [$($proc.Code)]" -ForegroundColor Red
    }
}
Write-Host ""

# --- 5. Delta funcional en primer paciente ---
Write-Host "[5/5] Calculando delta funcional (Barthel basal vs alta)..." -ForegroundColor Cyan

$firstFile = $bundles[0]
$b = Get-Content $firstFile.FullName -Raw | ConvertFrom-Json

$barthelObs = $b.entry |
    Where-Object { $_.resource.resourceType -eq "Observation" -and $_.resource.code.coding[0].code -eq "96761-3" } |
    Select-Object -ExpandProperty resource

if ($barthelObs.Count -ge 2) {
    $basal = $barthelObs[0].valueQuantity.value
    $alta  = $barthelObs[1].valueQuantity.value
    $delta = $alta - $basal
    Write-Host "  Paciente: $($firstFile.Name)" -ForegroundColor White
    Write-Host "    Barthel basal : $basal" -ForegroundColor Gray
    Write-Host "    Barthel alta  : $alta" -ForegroundColor Gray
    Write-Host "    Delta         : +$delta puntos" -ForegroundColor $(if ($delta -ge 0) { "Green" } else { "Red" })
} else {
    Write-Host "  No se encontraron 2 mediciones de Barthel en el primer bundle." -ForegroundColor Yellow
    Write-Host "  (normal si la poblacion es muy pequeña y el paciente no entro al modulo)" -ForegroundColor Yellow
}
Write-Host ""

# --- Resumen ---
Write-Host "========================================" -ForegroundColor Green
Write-Host "RESUMEN FINAL" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green

$allOK = ($totalObs -gt 0) -and ($totalProc -gt 0) -and ($totalCond -gt 0) -and ($scaleOK -eq $scales.Count) -and ($procOK -eq $procedures.Count)

if ($allOK) {
    Write-Host "ESTADO: MODULO OK - Todos los recursos y escalas presentes" -ForegroundColor Green
} else {
    Write-Host "ESTADO: PARCIAL - Revisa las escalas o procedimientos marcados como FALTA" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Causa mas comun: el modulo solo activa al 20% de pacientes (distributed_transition 0.20)." -ForegroundColor Yellow
    Write-Host "Si generaste pocos pacientes, aumenta la poblacion:" -ForegroundColor Yellow
    Write-Host "  .\scripts\generate-synthea.ps1 -Population 20" -ForegroundColor White
}

Write-Host ""
Write-Host "Proximos pasos DevOps:" -ForegroundColor Magenta
Write-Host "  git add ." -ForegroundColor White
Write-Host "  git commit -m 'feat: neurorehab module v2 final - all scales included'" -ForegroundColor White
Write-Host "  git push origin feature/neurorehab-module" -ForegroundColor White
Write-Host "  Nueva rama: feature/aws-terraform-foundation" -ForegroundColor White
Write-Host ""
