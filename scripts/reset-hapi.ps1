# scripts/reset-hapi.ps1
#
# Vacia TODOS los datos clinicos de HAPI FHIR (pacientes, hospital, medicos...)
# para poder volver a cargar el lote de datos desde cero sin duplicados.
#
# Como funciona: HAPI esta en una IP privada de la VPC y no se puede llamar
# desde tu ordenador. Por eso lanza una tarea puntual de Fargate con la imagen
# del loader (que ya sabe encontrar HAPI) y le pide a HAPI la operacion
# $expunge con expungeEverything. La tarea se apaga sola al terminar.
#
# Uso (desde la raiz del repo, con las credenciales del lab ya puestas):
#   .\scripts\reset-hapi.ps1
#
# Despues hay que volver a subir los ficheros de data/sample-fhir al bucket.

$ErrorActionPreference = "Stop"
$Region  = "us-east-1"
$Prefix  = "synthea-fhir-dev"
$Cluster = "$Prefix-cluster"
$Service = "$Prefix-loader-service"
$utf8    = New-Object System.Text.UTF8Encoding $false

# 1) La cola del loader debe estar vacia: si no, se cargarian datos a mitad.
$q = aws sqs get-queue-url --queue-name "$Prefix-loader-trigger-queue" --query QueueUrl --output text
$a = aws sqs get-queue-attributes --queue-url $q --attribute-names ApproximateNumberOfMessages ApproximateNumberOfMessagesNotVisible --output json | ConvertFrom-Json
$pend = [int]$a.Attributes.ApproximateNumberOfMessages + [int]$a.Attributes.ApproximateNumberOfMessagesNotVisible
if ($pend -gt 0) {
    throw "La cola del loader aun tiene $pend mensajes. Espera a que llegue a 0 y repite."
}

# 2) Red y definicion de tarea del servicio loader.
$svc = aws ecs describe-services --cluster $Cluster --services $Service --region $Region --output json | ConvertFrom-Json
$taskDef = $svc.services[0].taskDefinition
$net = $svc.services[0].networkConfiguration | ConvertTo-Json -Depth 10 -Compress

# 3) Orden que ejecutara la tarea puntual.
$py = @'
import loader, requests
u = loader.resolve_fhir_url()
print("EXPUNGE url", u, flush=True)
body = {"resourceType": "Parameters", "parameter": [{"name": "expungeEverything", "valueBoolean": True}]}
r = requests.post(u + "/$expunge", json=body, headers={"Content-Type": "application/fhir+json"}, timeout=900)
print("EXPUNGE status", r.status_code, r.text[:300].replace(chr(10), " "), flush=True)
t = requests.get(u + "/Patient?_summary=count", timeout=60).json().get("total")
print("EXPUNGE pacientes_restantes", t, flush=True)
'@
$ov = @{ containerOverrides = @( @{ name = "loader"; command = @("python", "-c", $py) } ) } | ConvertTo-Json -Depth 10 -Compress

$tmp = Join-Path $env:TEMP "reset-hapi"
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
[System.IO.File]::WriteAllText("$tmp\net.json", $net, $utf8)
[System.IO.File]::WriteAllText("$tmp\ov.json",  $ov,  $utf8)

# 4) Lanzar la tarea y esperar a que termine.
$run = aws ecs run-task --cluster $Cluster --launch-type FARGATE --task-definition $taskDef `
        --network-configuration "file://$tmp/net.json" --overrides "file://$tmp/ov.json" `
        --region $Region --output json | ConvertFrom-Json
if (-not $run.tasks -or $run.tasks.Count -eq 0) { throw "No se pudo lanzar la tarea: $($run.failures | ConvertTo-Json -Compress)" }
$taskArn = $run.tasks[0].taskArn
Write-Host "Tarea lanzada, esperando a que termine (1-3 min)..."
aws ecs wait tasks-stopped --cluster $Cluster --tasks $taskArn --region $Region

$res = aws ecs describe-tasks --cluster $Cluster --tasks $taskArn --region $Region --output json | ConvertFrom-Json
Write-Host "Codigo de salida: $($res.tasks[0].containers[0].exitCode)"
Start-Sleep -Seconds 10
Write-Host "--- Resultado ---"
aws logs tail "/ecs/$Prefix-loader" --since 10m --filter-pattern "EXPUNGE" --region $Region
