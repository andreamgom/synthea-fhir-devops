# scripts/test-query-api.ps1
#
# Prueba los endpoints de la Query API desplegada en ECS (Tabla 6 de la memoria).
#
# La Query API tiene una IP en la VPC y desde tu ordenador no se puede
# consultar con ec2:Describe* bloqueado en AWS Academy. Por eso lanza una
# tarea puntual de Fargate con la imagen del loader, dentro de la misma VPC,
# que hace las peticiones GET y escribe el resultado en CloudWatch.
#
# Uso (raiz del repo, credenciales del lab ya puestas):
#   .\scripts\test-query-api.ps1

$ErrorActionPreference = "Stop"
$Region  = "us-east-1"
$Prefix  = "synthea-fhir-dev"
$Cluster = "$Prefix-cluster"
$utf8    = New-Object System.Text.UTF8Encoding $false

# 1) IP privada de la tarea de query-api en ejecucion.
$taskArns = aws ecs list-tasks --cluster $Cluster --service-name "$Prefix-query-api-service" --desired-status RUNNING --region $Region --query "taskArns" --output json | ConvertFrom-Json
if (-not $taskArns -or $taskArns.Count -eq 0) { throw "No hay ninguna tarea RUNNING de query-api." }
$t = aws ecs describe-tasks --cluster $Cluster --tasks $taskArns[0] --region $Region --output json | ConvertFrom-Json
$ip = ($t.tasks[0].attachments[0].details | Where-Object { $_.name -eq "privateIPv4Address" }).value
if (-not $ip) { throw "No pude obtener la IP de la tarea de query-api." }
Write-Host "Query API en ${ip}:5000"

# 2) Red y definicion de tarea del loader (solo se usa para lanzar la tarea puntual).
$svc = aws ecs describe-services --cluster $Cluster --services "$Prefix-loader-service" --region $Region --output json | ConvertFrom-Json
$taskDef = $svc.services[0].taskDefinition
$net = $svc.services[0].networkConfiguration | ConvertTo-Json -Depth 10 -Compress

$py = @'
import requests
base = "http://__IP__:5000"
def show(path):
    try:
        r = requests.get(base + path, timeout=60)
        try:
            j = r.json()
        except Exception:
            j = None
        n = len(j["data"]) if isinstance(j, dict) and isinstance(j.get("data"), list) else (len(j) if isinstance(j, (list, dict)) else "-")
        txt = " ".join(r.text[:110].split()).encode("ascii", "replace").decode()
        print("QAPI", r.status_code, path, "| elementos:", n, "|", txt, flush=True)
        return j
    except Exception as e:
        print("QAPI ERROR", path, str(e)[:150], flush=True)
        return None
show("/")
show("/health")
pac = show("/api/pacientes")
show("/api/pacientes/neurorehab")
lista = pac.get("data", []) if isinstance(pac, dict) else (pac or [])
if lista:
    pid = lista[0].get("patient_id") if isinstance(lista[0], dict) else None
    if pid:
        show("/api/pacientes/" + pid + "/resumen")
for p in ["/api/escalas", "/api/episodios", "/api/procedimientos", "/api/diagnosticos"]:
    show(p)
'@
$py = $py.Replace("__IP__", $ip)
$ov = @{ containerOverrides = @( @{ name = "loader"; command = @("python", "-c", $py) } ) } | ConvertTo-Json -Depth 10 -Compress

$tmp = Join-Path $env:TEMP "test-query-api"
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
[System.IO.File]::WriteAllText("$tmp\net.json", $net, $utf8)
[System.IO.File]::WriteAllText("$tmp\ov.json",  $ov,  $utf8)

# 3) Lanzar la tarea y esperar.
$run = aws ecs run-task --cluster $Cluster --launch-type FARGATE --task-definition $taskDef `
        --network-configuration "file://$tmp/net.json" --overrides "file://$tmp/ov.json" `
        --region $Region --output json | ConvertFrom-Json
if (-not $run.tasks -or $run.tasks.Count -eq 0) { throw "No se pudo lanzar la tarea: $($run.failures | ConvertTo-Json -Compress)" }
Write-Host "Probando endpoints (1-2 min)..."
aws ecs wait tasks-stopped --cluster $Cluster --tasks $run.tasks[0].taskArn --region $Region
Start-Sleep -Seconds 15
Write-Host "--- Resultado ---"
aws logs tail "/ecs/$Prefix-loader" --since 10m --filter-pattern "QAPI" --region $Region
