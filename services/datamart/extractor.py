# services/datamart/extractor.py
# Extrae datos de HAPI FHIR vía REST API y construye los datamarts de neurorehabilitación.
#
# Modo por defecto (RUN_MODE=sqs): consumidor SQS long-polling sobre
# extractor-trigger-queue. El loader publica un mensaje en esta cola cada
# vez que carga un bundle con éxito; al recibirlo, el extractor relanza la
# extracción completa de los 5 datamarts (operación idempotente).
#
# Modo batch (RUN_MODE=batch): comportamiento original, una sola pasada,
# útil para desarrollo/pruebas locales sin infraestructura SQS.

import requests
import boto3
import json
import os
import logging
from pathlib import Path

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s"
)
log = logging.getLogger(__name__)

FHIR_URL = os.getenv("FHIR_SERVER_URL", "http://localhost:8080/fhir")
FHIR_SERVER_URL = FHIR_URL  # valor por defecto si no se puede resolver vía ECS

# Descubrimiento de HAPI FHIR vía ECS (alternativa a Cloud Map, bloqueado en Academy)
FHIR_ECS_CLUSTER = os.getenv("FHIR_ECS_CLUSTER", "")
FHIR_ECS_SERVICE = os.getenv("FHIR_ECS_SERVICE", "")
FHIR_PORT        = os.getenv("FHIR_PORT", "8080")
AWS_REGION = os.getenv("AWS_REGION", "us-east-1")
OUTPUT_DIR = os.getenv("OUTPUT_DIR", "./output")

# S3 buckets — one per datamart
S3_DM_PACIENTE      = os.getenv("S3_DM_PACIENTE",      "")
S3_DM_FUNCIONAL     = os.getenv("S3_DM_FUNCIONAL",     "")
S3_DM_EPISODIO      = os.getenv("S3_DM_EPISODIO",      "")
S3_DM_PROCEDIMIENTOS = os.getenv("S3_DM_PROCEDIMIENTOS", "")
S3_DM_DIAGNOSTICOS = os.getenv("S3_DM_DIAGNOSTICOS", "")

# Pipeline asíncrono SQS
RUN_MODE                    = os.getenv("RUN_MODE", "sqs")  # "sqs" | "batch"
EXTRACTOR_TRIGGER_QUEUE_URL = os.getenv("EXTRACTOR_TRIGGER_QUEUE_URL", "")
SQS_WAIT_TIME_SECONDS       = int(os.getenv("SQS_WAIT_TIME_SECONDS", "20"))
SQS_MAX_MESSAGES            = int(os.getenv("SQS_MAX_MESSAGES", "10"))

HEADERS = {"Accept": "application/fhir+json"}

ESCALAS = {
    "96761-3": "Barthel index",
    "72133-2": "Berg Balance Scale",
    "89386-5": "FAC",
    "72102-7": "PASS",
    "75304-5": "FOIS",
    "72106-8": "ACE-II",
    "83243-2": "FIM",
    "72105-0": "Fugl-Meyer",
    "72007-8": "EuroQol VAS",
    "39156-5": "IMC"
}

PROCEDIMIENTOS = {
    "36989003":  "Physiotherapy",
    "386053000": "Speech therapy",
    "410155007": "Neuropsychology",
    "84478008":  "Occupational therapy"
}

DIAGNOSTICOS_NEUROREHAB = {
    "422504002": "Ischemic stroke",
    "274100004": "Hemorrhagic stroke",
    "127295002": "Traumatic brain injury",
    "90584004":  "Spinal cord injury",
    "422768004": "Minimally conscious state",
    "128613002": "Other neurological condition"
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


def fetch_all(resource_type: str) -> list:
    results = []
    url = f"{FHIR_URL}/{resource_type}?_count=100"
    while url:
        resp = requests.get(url, headers=HEADERS, timeout=30)
        bundle = resp.json()
        for entry in bundle.get("entry", []):
            results.append(entry.get("resource", {}))
        url = next((l["url"] for l in bundle.get("link", []) if l["relation"] == "next"), None)
    return results


def build_dm_paciente(patients: list) -> list:
    rows = []
    for p in patients:
        nombre = apellido = ""
        for name in p.get("name", []):
            if name.get("use") == "official":
                apellido = name.get("family", "")
                nombre = (name.get("given") or [""])[0]
        rows.append({
            "patient_id": p.get("id"),
            "nombre":     nombre,
            "apellido":   apellido,
            "genero":     p.get("gender"),
            "fecha_nac":  p.get("birthDate")
        })
    return rows


def build_dm_funcional(observations: list) -> list:
    rows = []
    for obs in observations:
        for coding in obs.get("code", {}).get("coding", []):
            code = coding.get("code", "")
            if code in ESCALAS:
                rows.append({
                    "patient_id": obs.get("subject", {}).get("reference", "").replace("Patient/", ""),
                    "loinc_code": code,
                    "escala":     ESCALAS[code],
                    "valor":      obs.get("valueQuantity", {}).get("value"),
                    "fecha":      obs.get("effectiveDateTime", "")
                })
    return rows


def build_dm_episodio(encounters: list) -> list:
    rows = []
    for enc in encounters:
        periodo = enc.get("period", {})
        rows.append({
            "patient_id":   enc.get("subject", {}).get("reference", "").replace("Patient/", ""),
            "encounter_id": enc.get("id"),
            "tipo":         enc.get("class", {}).get("code"),
            "estado":       enc.get("status"),
            "fecha_inicio": periodo.get("start"),
            "fecha_fin":    periodo.get("end")
        })
    return rows


def build_dm_procedimientos(procedures: list) -> list:
    rows = []
    for proc in procedures:
        for coding in proc.get("code", {}).get("coding", []):
            code = coding.get("code", "")
            if code in PROCEDIMIENTOS:
                rows.append({
                    "patient_id":    proc.get("subject", {}).get("reference", "").replace("Patient/", ""),
                    "procedure_id":  proc.get("id"),
                    "snomed_code":   code,
                    "procedimiento": PROCEDIMIENTOS[code],
                    "estado":        proc.get("status"),
                    "fecha":         proc.get("performedDateTime", "")
                })
    return rows

def build_dm_diagnosticos(conditions: list) -> list:
    rows = []
    for cond in conditions:
        for coding in cond.get("code", {}).get("coding", []):
            code = coding.get("code", "")
            if code in DIAGNOSTICOS_NEUROREHAB:
                rows.append({
                    "patient_id":   cond.get("subject", {}).get("reference", "").replace("Patient/", ""),
                    "condition_id": cond.get("id"),
                    "snomed_code":  code,
                    "diagnostico":  DIAGNOSTICOS_NEUROREHAB[code],
                    "fecha_inicio": cond.get("onsetDateTime", ""),
                    "estado":       cond.get("clinicalStatus", {}).get("coding", [{}])[0].get("code", "")
                })
    return rows

def save_local(name: str, data: list):
    Path(OUTPUT_DIR).mkdir(parents=True, exist_ok=True)
    path = f"{OUTPUT_DIR}/{name}.json"
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    log.info(f"  → {len(data)} records saved locally to {path}")
    return path


def upload_to_s3(bucket: str, key: str, data: list):
    if not bucket:
        log.warning(f"  No S3 bucket configured for {key}, skipping upload")
        return
    s3 = boto3.client("s3", region_name=AWS_REGION)
    s3.put_object(
        Bucket=bucket,
        Key=key,
        Body=json.dumps(data, ensure_ascii=False, indent=2).encode("utf-8"),
        ContentType="application/json"
    )
    log.info(f"  → Uploaded to s3://{bucket}/{key}")


def run_extraction() -> None:
    """Ejecuta una pasada completa de extracción y reconstrucción de los 5 datamarts."""
    global FHIR_URL
    # La IP privada de HAPI FHIR cambia en cada despliegue: se resuelve en cada pasada
    FHIR_URL = resolve_fhir_url()
    log.info(f"Starting Extractor Builder — FHIR: {FHIR_URL}")

    log.info("Extracting patients...")
    patients = fetch_all("Patient")
    dm_paciente = build_dm_paciente(patients)
    save_local("dm_paciente", dm_paciente)
    upload_to_s3(S3_DM_PACIENTE, "dm_paciente.json", dm_paciente)

    log.info("Extracting observations...")
    observations = fetch_all("Observation")
    dm_funcional = build_dm_funcional(observations)
    save_local("dm_funcional", dm_funcional)
    upload_to_s3(S3_DM_FUNCIONAL, "dm_funcional.json", dm_funcional)

    log.info("Extracting encounters...")
    encounters = fetch_all("Encounter")
    dm_episodio = build_dm_episodio(encounters)
    save_local("dm_episodio", dm_episodio)
    upload_to_s3(S3_DM_EPISODIO, "dm_episodio.json", dm_episodio)

    log.info("Extracting procedures...")
    procedures = fetch_all("Procedure")
    dm_procedimientos = build_dm_procedimientos(procedures)
    save_local("dm_procedimientos", dm_procedimientos)
    upload_to_s3(S3_DM_PROCEDIMIENTOS, "dm_procedimientos.json", dm_procedimientos)

    log.info("Extracting conditions...")
    conditions = fetch_all("Condition")
    dm_diagnosticos = build_dm_diagnosticos(conditions)
    save_local("dm_diagnosticos", dm_diagnosticos)
    upload_to_s3(S3_DM_DIAGNOSTICOS, "dm_diagnosticos.json", dm_diagnosticos)

    log.info("✅ Extraction complete")
    log.info(f"   Patients:       {len(dm_paciente)}")
    log.info(f"   Clinical scales:{len(dm_funcional)}")
    log.info(f"   Episodes:       {len(dm_episodio)}")
    log.info(f"   Procedures:     {len(dm_procedimientos)}")
    log.info(f"   Diagnoses:      {len(dm_diagnosticos)}")


# ── PIPELINE ASÍNCRONO (SQS) ────────────────────────────────────────────

def consume() -> None:
    """Bucle principal: long-polling sobre extractor-trigger-queue.

    El loader publica un mensaje por cada bundle cargado con éxito, así que
    pueden llegar varios mensajes seguidos por una misma tanda de datos. Se
    recogen todos los que estén disponibles y se lanza UNA sola extracción
    para esa ronda (la extracción reconstruye los datamarts completos, por
    lo que relanzarla varias veces seguidas es idempotente pero innecesario).
    """
    if not EXTRACTOR_TRIGGER_QUEUE_URL:
        raise RuntimeError("EXTRACTOR_TRIGGER_QUEUE_URL no configurada")

    sqs_client = boto3.client("sqs", region_name=AWS_REGION)

    log.info(f"Extractor escuchando en {EXTRACTOR_TRIGGER_QUEUE_URL} — FHIR: {FHIR_ECS_SERVICE or FHIR_URL}")

    while True:
        response = sqs_client.receive_message(
            QueueUrl=EXTRACTOR_TRIGGER_QUEUE_URL,
            MaxNumberOfMessages=SQS_MAX_MESSAGES,
            WaitTimeSeconds=SQS_WAIT_TIME_SECONDS
        )
        messages = response.get("Messages", [])
        if not messages:
            continue

        log.info(f"Disparo recibido ({len(messages)} mensaje(s)) — relanzando extracción")
        try:
            run_extraction()
        except Exception as e:
            log.error(f"❌ Error durante la extracción: {e}")
            # No se borran los mensajes: se reintenta tras el visibility timeout
            continue

        for msg in messages:
            sqs_client.delete_message(
                QueueUrl=EXTRACTOR_TRIGGER_QUEUE_URL,
                ReceiptHandle=msg["ReceiptHandle"]
            )


def main():
    if RUN_MODE == "batch":
        run_extraction()
    else:
        consume()


if __name__ == "__main__":
    main()
