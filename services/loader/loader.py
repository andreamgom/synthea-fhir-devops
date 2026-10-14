# services/loader/loader.py
# Lee bundles FHIR desde S3 y los carga en HAPI FHIR.
#
# Modo por defecto (RUN_MODE=sqs): consumidor SQS long-polling sobre
# loader-trigger-queue. Cada mensaje corresponde a un objeto nuevo subido
# al datalake (evento S3 ObjectCreated). Al cargar un bundle con éxito,
# publica un mensaje en extractor-trigger-queue para disparar al extractor.
#
# Modo batch (RUN_MODE=batch): comportamiento original, útil para
# desarrollo/pruebas locales sin infraestructura SQS.

import boto3
import requests
import json
import os
import logging
from pathlib import Path
from urllib.parse import unquote_plus

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s"
)
log = logging.getLogger(__name__)

# Configuración desde variables de entorno
FHIR_SERVER_URL = os.getenv("FHIR_SERVER_URL", "http://localhost:8080/fhir")

# Descubrimiento de HAPI FHIR vía ECS (alternativa a Cloud Map, bloqueado en Academy)
FHIR_ECS_CLUSTER = os.getenv("FHIR_ECS_CLUSTER", "")
FHIR_ECS_SERVICE = os.getenv("FHIR_ECS_SERVICE", "")
FHIR_PORT        = os.getenv("FHIR_PORT", "8080")
LOAD_TIMEOUT_SECONDS = int(os.getenv("LOAD_TIMEOUT_SECONDS", "300"))
S3_BUCKET       = os.getenv("S3_BUCKET", "synthea-fhir-dev-datalake-547c2ee6")
S3_PREFIX       = os.getenv("S3_PREFIX", "raw/fhir/")
AWS_REGION      = os.getenv("AWS_REGION", "us-east-1")

# Pipeline asíncrono SQS
RUN_MODE                    = os.getenv("RUN_MODE", "sqs")  # "sqs" | "batch"
LOADER_TRIGGER_QUEUE_URL    = os.getenv("LOADER_TRIGGER_QUEUE_URL", "")
EXTRACTOR_TRIGGER_QUEUE_URL = os.getenv("EXTRACTOR_TRIGGER_QUEUE_URL", "")
SQS_WAIT_TIME_SECONDS       = int(os.getenv("SQS_WAIT_TIME_SECONDS", "20"))
SQS_MAX_MESSAGES            = int(os.getenv("SQS_MAX_MESSAGES", "5"))

HEADERS = {
    "Content-Type": "application/fhir+json",
    "Accept": "application/fhir+json"
}


def resolve_fhir_url() -> str:
    """Devuelve la URL base de HAPI FHIR.

    AWS Academy bloquea AWS Cloud Map (servicediscovery:*), así que no hay un
    nombre DNS interno estable para el servicio fhir-server. Si se configuran
    FHIR_ECS_CLUSTER y FHIR_ECS_SERVICE, se consulta a ECS la IP privada de la
    tarea en ejecución de ese servicio. Esa IP cambia en cada despliegue, por
    eso se resuelve en cada uso y no una sola vez al arrancar.

    Si no hay configuración ECS (desarrollo local) o la consulta falla, se usa
    FHIR_SERVER_URL; en ese caso la carga fallará de forma segura y el mensaje
    SQS volverá a la cola para reintentarse.
    """
    if not (FHIR_ECS_CLUSTER and FHIR_ECS_SERVICE):
        return FHIR_SERVER_URL
    try:
        ecs = boto3.client("ecs", region_name=AWS_REGION)
        task_arns = ecs.list_tasks(
            cluster=FHIR_ECS_CLUSTER,
            serviceName=FHIR_ECS_SERVICE,
            desiredStatus="RUNNING",
        ).get("taskArns", [])
        if task_arns:
            tasks = ecs.describe_tasks(cluster=FHIR_ECS_CLUSTER, tasks=task_arns).get("tasks", [])
            for task in tasks:
                if task.get("lastStatus") != "RUNNING":
                    continue
                for attachment in task.get("attachments", []):
                    for detail in attachment.get("details", []):
                        if detail.get("name") == "privateIPv4Address":
                            return f"http://{detail['value']}:{FHIR_PORT}/fhir"
        log.warning(f"No hay ninguna tarea RUNNING de {FHIR_ECS_SERVICE} en {FHIR_ECS_CLUSTER}")
    except Exception as e:
        log.warning(f"No se pudo resolver la IP de HAPI FHIR vía ECS: {e}")
    return FHIR_SERVER_URL


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
            timeout=LOAD_TIMEOUT_SECONDS
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


# ── PIPELINE ASÍNCRONO (SQS) ────────────────────────────────────────────

def notify_extractor(sqs_client, filename: str) -> None:
    """Publica en extractor-trigger-queue para avisar de que hay datos nuevos."""
    if not EXTRACTOR_TRIGGER_QUEUE_URL:
        log.warning("EXTRACTOR_TRIGGER_QUEUE_URL no configurada, no se notifica al extractor")
        return
    try:
        sqs_client.send_message(
            QueueUrl=EXTRACTOR_TRIGGER_QUEUE_URL,
            MessageBody=json.dumps({"source": "loader", "bundle": filename})
        )
        log.info(f"  → Extractor notificado (bundle: {filename})")
    except Exception as e:
        log.error(f"  No se pudo notificar al extractor: {e}")


def _extract_s3_records(body: str) -> list:
    """Extrae (bucket, key) de una notificación de evento S3 recibida vía SQS."""
    try:
        payload = json.loads(body)
    except (json.JSONDecodeError, TypeError):
        return []

    if payload.get("Event") == "s3:TestEvent":
        # Mensaje de verificación que S3 envía al crear la notificación
        return []

    records = []
    for record in payload.get("Records", []):
        s3_info = record.get("s3", {})
        bucket = s3_info.get("bucket", {}).get("name")
        key = s3_info.get("object", {}).get("key")
        if bucket and key:
            records.append((bucket, unquote_plus(key)))
    return records


def process_bundle_key(s3_client, sqs_client, fhir_url: str, bucket: str, key: str) -> bool:
    """Descarga un bundle de S3, lo carga en FHIR y notifica al extractor si tiene éxito."""
    filename = Path(key).name
    if not filename.endswith(".json"):
        return True

    obj_data = s3_client.get_object(Bucket=bucket, Key=key)
    bundle = json.loads(obj_data["Body"].read())

    ok = load_bundle(fhir_url, bundle, filename)
    if ok:
        notify_extractor(sqs_client, filename)
    return ok


def consume() -> None:
    """Bucle principal: long-polling sobre loader-trigger-queue."""
    if not LOADER_TRIGGER_QUEUE_URL:
        raise RuntimeError("LOADER_TRIGGER_QUEUE_URL no configurada")

    s3_client = boto3.client("s3", region_name=AWS_REGION)
    sqs_client = boto3.client("sqs", region_name=AWS_REGION)

    log.info(f"Loader escuchando en {LOADER_TRIGGER_QUEUE_URL} — FHIR: {FHIR_ECS_SERVICE or FHIR_SERVER_URL}")

    while True:
        response = sqs_client.receive_message(
            QueueUrl=LOADER_TRIGGER_QUEUE_URL,
            MaxNumberOfMessages=SQS_MAX_MESSAGES,
            WaitTimeSeconds=SQS_WAIT_TIME_SECONDS
        )
        messages = response.get("Messages", [])
        if not messages:
            continue

        # La IP privada de HAPI FHIR cambia en cada despliegue: se resuelve por mensaje
        fhir_url = resolve_fhir_url()

        for msg in messages:
            records = _extract_s3_records(msg.get("Body", ""))
            success = True
            for bucket, key in records:
                try:
                    if not process_bundle_key(s3_client, sqs_client, fhir_url, bucket, key):
                        success = False
                except Exception as e:
                    log.error(f"❌ Error procesando {key}: {e}")
                    success = False

            # El mensaje solo se borra si el bundle se cargó bien. Si falla
            # (p. ej. porque referencia un Organization/Practitioner que aún
            # no existe), el mensaje vuelve a ser visible tras el visibility
            # timeout y se reintenta — así se resuelve de forma natural el
            # orden hospitalInformation/practitionerInformation → pacientes.
            if success:
                sqs_client.delete_message(
                    QueueUrl=LOADER_TRIGGER_QUEUE_URL,
                    ReceiptHandle=msg["ReceiptHandle"]
                )


# ── MODO BATCH (desarrollo/pruebas locales sin SQS) ─────────────────────

def run_batch() -> None:
    """Comportamiento original: carga todo lo que haya en S3 en una pasada."""
    log.info(f"Iniciando loader (batch) — FHIR: {FHIR_SERVER_URL} | S3: s3://{S3_BUCKET}/{S3_PREFIX}")

    s3_client = boto3.client("s3", region_name=AWS_REGION)

    load_priority_bundle(s3_client, "hospitalInformation")
    load_priority_bundle(s3_client, "practitionerInformation")

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


def main():
    if RUN_MODE == "batch":
        run_batch()
    else:
        consume()


if __name__ == "__main__":
    main()
