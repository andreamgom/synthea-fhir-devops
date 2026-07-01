# services/datamart/extractor.py
# Extracts data from HAPI FHIR via REST API and builds neurorehab datamarts

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
AWS_REGION = os.getenv("AWS_REGION", "us-east-1")
OUTPUT_DIR = os.getenv("OUTPUT_DIR", "./output")

# S3 buckets — one per datamart
S3_DM_PACIENTE      = os.getenv("S3_DM_PACIENTE",      "")
S3_DM_FUNCIONAL     = os.getenv("S3_DM_FUNCIONAL",     "")
S3_DM_EPISODIO      = os.getenv("S3_DM_EPISODIO",      "")
S3_DM_PROCEDIMIENTOS = os.getenv("S3_DM_PROCEDIMIENTOS", "")
S3_DM_DIAGNOSTICOS = os.getenv("S3_DM_DIAGNOSTICOS", "")

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


def main():
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
    log.info(f"   Diagnoses:      {len(dm_diagnosticos)}")

    log.info("✅ Extraction complete")
    log.info(f"   Patients:       {len(dm_paciente)}")
    log.info(f"   Clinical scales:{len(dm_funcional)}")
    log.info(f"   Episodes:       {len(dm_episodio)}")
    log.info(f"   Procedures:     {len(dm_procedimientos)}")


if __name__ == "__main__":
    main()