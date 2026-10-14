# scripts/lab-session.ps1
#
# Prepara tu PowerShell cada vez que arrancas el AWS Academy Learner Lab.
#
# Uso:
#   1. En AWS Academy: Start Lab -> AWS Details -> "AWS CLI: Show".
#   2. Copia ese bloque ([default] aws_access_key_id=... etc.) y pegalo en
#         %USERPROFILE%\.aws\credentials
#      sustituyendo todo lo que hubiera antes. Guarda el archivo.
#   3. Desde la raiz del repo, en PowerShell, ejecuta (CON el punto inicial):
#         . .\scripts\lab-session.ps1
#      El punto es importante: asi las variables quedan cargadas en tu
#      ventana actual y puedes seguir con terraform en ella.
#
# Que hace:
#   - Carga las credenciales del lab en la sesion actual.
#   - Comprueba que funcionan y te dice el numero de cuenta.
#   - Ajusta el lab_role_arn de terraform/terraform.tfvars a esa cuenta.
#   - Si tienes GitHub CLI (gh) instalado y con sesion iniciada, actualiza
#     los 3 secrets AWS_* del repositorio. Si no, te avisa para hacerlo a mano.
#
# No toca vpc_id ni subnet_ids: el laboratorio no permite consultarlos por
# linea de comandos, asi que si cambia la cuenta hay que copiarlos de la
# consola (VPC -> Your VPCs / Subnets) a terraform/terraform.tfvars.

$ErrorActionPreference = "Stop"
$Repo = "andreamgom/synthea-fhir-devops"

$credFile = Join-Path $env:USERPROFILE ".aws\credentials"
if (-not (Test-Path $credFile)) {
    throw "No existe $credFile. Pega ahi el bloque 'AWS CLI' del Learner Lab (paso 2)."
}

function Get-CredValue([string]$name) {
    $line = Select-String -Path $credFile -Pattern "^\s*$name\s*=\s*(.+)$" | Select-Object -First 1
    if (-not $line) { throw "No encuentro '$name' en $credFile" }
    return $line.Matches[0].Groups[1].Value.Trim()
}

$accessKey = Get-CredValue "aws_access_key_id"
$secretKey = Get-CredValue "aws_secret_access_key"
$token     = Get-CredValue "aws_session_token"

$env:AWS_ACCESS_KEY_ID     = $accessKey
$env:AWS_SECRET_ACCESS_KEY = $secretKey
$env:AWS_SESSION_TOKEN     = $token
$env:AWS_DEFAULT_REGION    = "us-east-1"

# 1) Comprobar que las credenciales funcionan
$account = aws sts get-caller-identity --query Account --output text
if ($LASTEXITCODE -ne 0 -or -not $account) {
    throw "Las credenciales no funcionan (caducadas o mal copiadas). Vuelve a copiarlas desde AWS Details."
}
Write-Host "Credenciales OK. Cuenta AWS: $account" -ForegroundColor Green

# 2) Sincronizar lab_role_arn en terraform.tfvars
$tfvars = Join-Path $PSScriptRoot "..\terraform\terraform.tfvars"
if (Test-Path $tfvars) {
    $content = Get-Content $tfvars -Raw
    $updated = $content -replace 'arn:aws:iam::\d{12}:role/LabRole', "arn:aws:iam::${account}:role/LabRole"
    if ($updated -ne $content) {
        Set-Content -Path $tfvars -Value $updated -NoNewline -Encoding ascii
        Write-Host "terraform.tfvars: lab_role_arn actualizado a la cuenta $account" -ForegroundColor Yellow
        Write-Warning "La cuenta ha cambiado: revisa tambien vpc_id y subnet_ids en terraform.tfvars (copialos de la consola de AWS)."
    } else {
        Write-Host "terraform.tfvars: lab_role_arn ya coincide con la cuenta." -ForegroundColor Green
    }
} else {
    Write-Warning "No encuentro terraform\terraform.tfvars, me salto ese paso."
}

# 3) Actualizar los secrets de GitHub (si hay gh disponible)
if (Get-Command gh -ErrorAction SilentlyContinue) {
    gh auth status *> $null
    if ($LASTEXITCODE -eq 0) {
        $accessKey | gh secret set AWS_ACCESS_KEY_ID     --repo $Repo
        $secretKey | gh secret set AWS_SECRET_ACCESS_KEY --repo $Repo
        $token     | gh secret set AWS_SESSION_TOKEN     --repo $Repo
        Write-Host "Secrets de GitHub actualizados en $Repo" -ForegroundColor Green
    } else {
        Write-Warning "gh esta instalado pero sin sesion. Ejecuta 'gh auth login' y vuelve a lanzar el script."
    }
} else {
    Write-Warning "GitHub CLI (gh) no esta instalado. Actualiza a mano los secrets AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY y AWS_SESSION_TOKEN en GitHub (Settings -> Secrets and variables -> Actions)."
}

Write-Host "Listo. Esta sesion de PowerShell ya puede usar aws y terraform." -ForegroundColor Green
