# services/loader/loader.py
# Lee bundles FHIR desde S3 y los carga en HAPI FHIR

import boto3
import requests
import json
import os
import logging
from pathlib import Path

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s"
)
log = logging.getLogger(__name__)

# Configuración desde variables de entorno
FHIR_SERVER_URL = os.getenv("FHIR_SERVER_URL", "http://localhost:8080/fhir")
S3_BUCKET       = os.getenv("S3_BUCKET", "synthea-fhir-dev-datalake-547c2ee6")
S3_PREFIX       = os.getenv("S3_PREFIX", "raw/fhir/")
AWS_REGION      = os.getenv("AWS_REGION", "us-east-1")

HEADERS = {
    "Content-Type": "application/fhir+json",
    "Accept": "application/fhir+json"
}


def list_bundles(s3_client) -> list[str]:
    """Lista todos los bundles FHIR en S3, excluyendo hospital y practitioner."""
    response = s3_client.list_objects_v2(Bucket=S3_BUCKET, Prefix=S3_PREFIX)
    keys = []
    for obj in response.get("Contents", []):
        key = obj["Key"]
        name = Path(key).name
        if name.endswith(".json") and "hospital" not in name and "practitioner" not in name:
            keys.append(key)
    log.info(f"Encontrados {len(keys)} bundles de pacientes en S3")
    return keys


def load_bundle(fhir_url: str, bundle: dict, filename: str) -> bool:
    """Carga un bundle FHIR en el servidor mediante POST."""
    try:
        response = requests.post(
            fhir_url,
            headers=HEADERS,
            data=json.dumps(bundle),
            timeout=60
        )
        if response.status_code in (200, 201):
            log.info(f"✅ {filename} cargado correctamente")
            return True
        else:
            log.error(f"❌ {filename} — HTTP {response.status_code}: {response.text[:200]}")
            return False
    except requests.exceptions.RequestException as e:
        log.error(f"❌ {filename} — Error de conexión: {e}")
        return False


def load_priority_bundle(s3_client, keyword: str) -> None:
    """Carga hospitalInformation o practitionerInformation primero."""
    response = s3_client.list_objects_v2(Bucket=S3_BUCKET, Prefix=S3_PREFIX)
    for obj in response.get("Contents", []):
        key = obj["Key"]
        if keyword in Path(key).name:
            log.info(f"Cargando bundle prioritario: {key}")
            obj_data = s3_client.get_object(Bucket=S3_BUCKET, Key=key)
            bundle = json.loads(obj_data["Body"].read())
            load_bundle(FHIR_SERVER_URL, bundle, Path(key).name)
            return


def main():
    log.info(f"Iniciando loader — FHIR: {FHIR_SERVER_URL} | S3: s3://{S3_BUCKET}/{S3_PREFIX}")

    s3_client = boto3.client("s3", region_name=AWS_REGION)

    # 1. Cargar hospitalInformation primero
    load_priority_bundle(s3_client, "hospitalInformation")

    # 2. Cargar practitionerInformation
    load_priority_bundle(s3_client, "practitionerInformation")

    # 3. Cargar bundles de pacientes
    keys = list_bundles(s3_client)
    ok = 0
    ko = 0
    for key in keys:
        obj_data = s3_client.get_object(Bucket=S3_BUCKET, Key=key)
        bundle = json.loads(obj_data["Body"].read())
        if load_bundle(FHIR_SERVER_URL, bundle, Path(key).name):
            ok += 1
        else:
            ko += 1

    log.info(f"Carga completada — ✅ {ok} correctos | ❌ {ko} errores")


if __name__ == "__main__":
    main()
