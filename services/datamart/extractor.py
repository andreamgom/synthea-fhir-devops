# services/datamart/extractor.py
# Extrae datos de HAPI FHIR via API REST y genera datamarts en JSON

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

FHIR_URL   = os.getenv("FHIR_SERVER_URL", "http://localhost:8080/fhir")
OUTPUT_DIR = os.getenv("OUTPUT_DIR", "./output")
HEADERS    = {"Accept": "application/fhir+json"}

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
            "patient_id":  p.get("id"),
            "nombre":      nombre,
            "apellido":    apellido,
            "genero":      p.get("gender"),
            "fecha_nac":   p.get("birthDate")
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


def save(name: str, data: list):
    Path(OUTPUT_DIR).mkdir(parents=True, exist_ok=True)
    path = f"{OUTPUT_DIR}/{name}.json"
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    log.info(f"  → {len(data)} registros guardados en {path}")


def main():
    log.info(f"Iniciando extractor — FHIR: {FHIR_URL}")

    log.info("Extrayendo pacientes...")
    patients = fetch_all("Patient")
    save("dm_paciente", build_dm_paciente(patients))

    log.info("Extrayendo observaciones...")
    observations = fetch_all("Observation")
    dm_func = build_dm_funcional(observations)
    save("dm_funcional", dm_func)

    log.info("Extrayendo episodios...")
    encounters = fetch_all("Encounter")
    save("dm_episodio", build_dm_episodio(encounters))

    log.info("✅ Extracción completada")
    log.info(f"   Pacientes:    {len(patients)}")
    log.info(f"   Escalas:      {len(dm_func)}")
    log.info(f"   Episodios:    {len(encounters)}")


if __name__ == "__main__":
    main()