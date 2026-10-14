# scripts/run-integration-tests.ps1
#
# Ejecuta los 6 tests de integracion (tests/test_fhir_integration.py) contra
# el HAPI FHIR REAL desplegado en ECS. HAPI esta en una IP privada de la VPC,
# asi que el script lanza una tarea puntual de Fargate con la imagen del
# loader, le pasa los ficheros de tests y ejecuta pytest alli dentro.
#
# Uso (raiz del repo, credenciales del lab ya puestas):
#   .\scripts\run-integration-tests.ps1

$ErrorActionPreference = "Stop"
$Region  = "us-east-1"
$Prefix  = "synthea-fhir-dev"
$Cluster = "$Prefix-cluster"
$Root    = Join-Path $PSScriptRoot ".."
$utf8    = New-Object System.Text.UTF8Encoding $false

function B64([string]$path) { [Convert]::ToBase64String([System.IO.File]::ReadAllBytes((Join-Path $Root $path))) }
$files = '{"conftest.py":"' + (B64 "tests\conftest.py") + '","test_fhir_integration.py":"' + (B64 "tests\test_fhir_integration.py") + '","pytest.ini":"' + (B64 "pytest.ini") + '"}'

$py = @'
import base64, os, subprocess, sys
import loader
FILES = __FILES__
subprocess.run([sys.executable, "-m", "pip", "install", "-q", "pytest==7.4.0", "pytest-timeout==2.2.0"], check=True)
os.makedirs("/tmp/t", exist_ok=True)
for n, c in FILES.items():
    open("/tmp/t/" + n, "wb").write(base64.b64decode(c))
os.environ["FHIR_SERVER_URL"] = loader.resolve_fhir_url()
print("ITEST HAPI", os.environ["FHIR_SERVER_URL"], flush=True)
p = subprocess.run([sys.executable, "-m", "pytest", "/tmp/t", "-v", "-p", "no:cacheprovider", "-m", "integration"],
                   capture_output=True, text=True, cwd="/tmp/t")
for l in (p.stdout + p.stderr).splitlines():
    print("ITEST", l.encode("ascii", "replace").decode(), flush=True)
print("ITEST exit", p.returncode, flush=True)
'@
$py = $py.Replace("__FILES__", $files)

$svc = aws ecs describe-services --cluster $Cluster --services "$Prefix-loader-service" --region $Region --output json | ConvertFrom-Json
$taskDef = $svc.services[0].taskDefinition
$net = $svc.services[0].networkConfiguration | ConvertTo-Json -Depth 10 -Compress
$ov = @{ containerOverrides = @( @{ name = "loader"; command = @("python", "-c", $py) } ) } | ConvertTo-Json -Depth 10 -Compress
if ($ov.Length -gt 8000) { throw "La orden supera el limite de ECS ($($ov.Length) caracteres)." }

$tmp = Join-Path $env:TEMP "run-integration-tests"
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
[System.IO.File]::WriteAllText("$tmp\net.json", $net, $utf8)
[System.IO.File]::WriteAllText("$tmp\ov.json",  $ov,  $utf8)

$run = aws ecs run-task --cluster $Cluster --launch-type FARGATE --task-definition $taskDef `
        --network-configuration "file://$tmp/net.json" --overrides "file://$tmp/ov.json" `
        --region $Region --output json | ConvertFrom-Json
if (-not $run.tasks -or $run.tasks.Count -eq 0) { throw "No se pudo lanzar la tarea: $($run.failures | ConvertTo-Json -Compress)" }
Write-Host "Ejecutando tests de integracion contra HAPI (1-3 min)..."
aws ecs wait tasks-stopped --cluster $Cluster --tasks $run.tasks[0].taskArn --region $Region
Start-Sleep -Seconds 15
Write-Host "--- Resultado ---"
aws logs tail "/ecs/$Prefix-loader" --since 10m --filter-pattern "ITEST" --region $Region
