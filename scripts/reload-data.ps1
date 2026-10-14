# scripts/reload-data.ps1
#
# Carga el lote de datos de data/sample-fhir en la plataforma y espera a que
# todo el flujo termine, sin que tengas que ir mirando logs:
#   1) sube hospital y medicos y espera a que el loader los procese;
#   2) sube los pacientes (menos Ninfa662, su bundle de 38 MB supera el
#      timeout del loader) y espera a que las colas se vacien;
#   3) lee los 5 datamarts de S3 y muestra el resumen.
#
# Uso (raiz del repo, credenciales del lab ya puestas):
#   .\scripts\reload-data.ps1
#
# Tarda unos 10-15 minutos. Esta pensado para ejecutarse con HAPI vacia o
# con los datos ya cargados: los bundles de hospital y medicos no se duplican.

$ErrorActionPreference = "Stop"
$Region  = "us-east-1"
$Prefix  = "synthea-fhir-dev"
$Suffix  = "149668cb"
$Lake    = "s3://$Prefix-fhir-datalake-$Suffix/raw/fhir/"
$Data    = Join-Path $PSScriptRoot "..\data\sample-fhir"
$Esperado = 19

function Get-QueueUrl([string]$name) {
    aws sqs get-queue-url --queue-name "$Prefix-$name" --query QueueUrl --output text
}
function Get-Pending([string]$url) {
    $a = aws sqs get-queue-attributes --queue-url $url --attribute-names ApproximateNumberOfMessages ApproximateNumberOfMessagesNotVisible --output json | ConvertFrom-Json
    return [int]$a.Attributes.ApproximateNumberOfMessages + [int]$a.Attributes.ApproximateNumberOfMessagesNotVisible
}
# Espera a que las colas indicadas lleguen a 0 mensajes 3 comprobaciones seguidas.
function Wait-QueuesEmpty([string[]]$urls, [int]$maxMinutes, [string]$label) {
    $limit = (Get-Date).AddMinutes($maxMinutes)
    $zeros = 0
    while ((Get-Date) -lt $limit) {
        $total = 0
        foreach ($u in $urls) { $total += Get-Pending $u }
        if ($total -eq 0) { $zeros++ } else { $zeros = 0 }
        Write-Host ("  {0}: {1} mensajes pendientes" -f $label, $total)
        if ($zeros -ge 3) { return $true }
        Start-Sleep -Seconds 20
    }
    return $false
}
function Read-Datamart([string]$name) {
    $json = aws s3 cp "s3://$Prefix-dm-$name-$Suffix/dm_$name.json" - | Out-String
    return ($json | ConvertFrom-Json)
}

$qLoader    = Get-QueueUrl "loader-trigger-queue"
$qExtractor = Get-QueueUrl "extractor-trigger-queue"

# 0) Las colas deben estar vacias antes de empezar.
if ((Get-Pending $qLoader) -gt 0) { throw "La cola del loader no esta vacia. Espera a que llegue a 0 y repite." }

# 1) Hospital y medicos.
Write-Host "1/3 Subiendo hospital y medicos..."
aws s3 cp (Join-Path $Data "hospitalInformation1782908683103.json")   $Lake | Out-Null
aws s3 cp (Join-Path $Data "practitionerInformation1782908683103.json") $Lake | Out-Null
Start-Sleep -Seconds 20   # margen para que S3 avise a la cola
if (-not (Wait-QueuesEmpty @($qLoader) 10 "loader")) { throw "Hospital/medicos no terminaron de cargar en 10 min." }

# 2) Pacientes (sin Ninfa662).
Write-Host "2/3 Subiendo pacientes..."
aws s3 cp $Data $Lake --recursive --exclude "hospitalInformation*" --exclude "practitionerInformation*" --exclude "Ninfa662*" | Out-Null
Start-Sleep -Seconds 20
if (-not (Wait-QueuesEmpty @($qLoader, $qExtractor) 40 "loader+extractor")) {
    Write-Warning "Las colas no se vaciaron en 40 min; muestro lo que haya."
}

# 3) Resumen de datamarts (el extractor puede tardar un poco mas tras vaciar la cola).
Write-Host "3/3 Leyendo datamarts..."
$pac = $null
for ($i = 0; $i -lt 12; $i++) {
    $pac = Read-Datamart "paciente"
    if (@($pac).Count -eq $Esperado) { break }
    Write-Host ("  dm_paciente tiene {0} filas, esperando {1}..." -f @($pac).Count, $Esperado)
    Start-Sleep -Seconds 20
}

Write-Host ""
Write-Host "=== RESUMEN ==="
foreach ($d in "paciente","funcional","episodio","procedimientos","diagnosticos") {
    $rows = Read-Datamart $d
    Write-Host ("{0,-15}: {1} filas" -f $d, @($rows).Count)
}
$ids = @($pac | ForEach-Object { $_.patient_id } | Sort-Object -Unique).Count
Write-Host ""
Write-Host ("Pacientes distintos en dm_paciente: {0} (esperado {1})" -f $ids, $Esperado)
Write-Host ""
Write-Host "=== Diagnosticos de neurorrehabilitacion ==="
Read-Datamart "diagnosticos" | Group-Object diagnostico | Sort-Object Count -Descending | Select-Object Count, Name | Format-Table -AutoSize
if ($ids -eq $Esperado) { Write-Host "OK: la carga esta completa." -ForegroundColor Green }
else { Write-Host "ATENCION: no coincide con lo esperado." -ForegroundColor Yellow }
