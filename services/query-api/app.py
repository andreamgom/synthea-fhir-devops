# services/query-api/app.py
# Extractor Query API - serves neurorehab datamarts via REST

import boto3
import json
import os
import logging
from flask import Flask, jsonify, request, send_from_directory
from functools import lru_cache

logging.basicConfig(level=logging.INFO)
log = logging.getLogger(__name__)

app = Flask(__name__)

AWS_REGION           = os.getenv("AWS_REGION", "us-east-1")
S3_DM_PACIENTE       = os.getenv("S3_DM_PACIENTE", "")
S3_DM_FUNCIONAL      = os.getenv("S3_DM_FUNCIONAL", "")
S3_DM_EPISODIO       = os.getenv("S3_DM_EPISODIO", "")
S3_DM_PROCEDIMIENTOS = os.getenv("S3_DM_PROCEDIMIENTOS", "")


def read_s3(bucket: str, key: str) -> list:
    s3 = boto3.client("s3", region_name=AWS_REGION)
    obj = s3.get_object(Bucket=bucket, Key=key)
    return json.loads(obj["Body"].read())


def read_local(filename: str) -> list:
    path = f"../datamart/output/{filename}"
    if os.path.exists(path):
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    return []


def get_data(bucket: str, key: str, local_file: str) -> list:
    if bucket:
        try:
            return read_s3(bucket, key)
        except Exception as e:
            log.warning(f"S3 read failed: {e}, falling back to local")
    return read_local(local_file)


@app.route("/")
def index():
    return send_from_directory("static", "index.html")


@app.route("/health")
def health():
    return jsonify({"status": "ok", "service": "Extractor Query API"})


@app.route("/api/pacientes")
def get_pacientes():
    data = get_data(S3_DM_PACIENTE, "dm_paciente.json", "dm_paciente.json")
    patient_id = request.args.get("patient_id")
    if patient_id:
        data = [p for p in data if p.get("patient_id") == patient_id]
    return jsonify({"total": len(data), "data": data})


@app.route("/api/escalas")
def get_escalas():
    data = get_data(S3_DM_FUNCIONAL, "dm_funcional.json", "dm_funcional.json")
    patient_id = request.args.get("patient_id")
    escala     = request.args.get("escala")
    if patient_id:
        data = [r for r in data if r.get("patient_id") == patient_id]
    if escala:
        data = [r for r in data if escala.lower() in r.get("escala", "").lower()]
    return jsonify({"total": len(data), "data": data})


@app.route("/api/episodios")
def get_episodios():
    data = get_data(S3_DM_EPISODIO, "dm_episodio.json", "dm_episodio.json")
    patient_id = request.args.get("patient_id")
    if patient_id:
        data = [r for r in data if r.get("patient_id") == patient_id]
    return jsonify({"total": len(data), "data": data})


@app.route("/api/procedimientos")
def get_procedimientos():
    data = get_data(S3_DM_PROCEDIMIENTOS, "dm_procedimientos.json", "dm_procedimientos.json")
    patient_id = request.args.get("patient_id")
    if patient_id:
        data = [r for r in data if r.get("patient_id") == patient_id]
    return jsonify({"total": len(data), "data": data})


@app.route("/api/pacientes/<patient_id>/resumen")
def get_resumen_paciente(patient_id):
    pacientes     = get_data(S3_DM_PACIENTE, "dm_paciente.json", "dm_paciente.json")
    escalas       = get_data(S3_DM_FUNCIONAL, "dm_funcional.json", "dm_funcional.json")
    episodios     = get_data(S3_DM_EPISODIO, "dm_episodio.json", "dm_episodio.json")
    procedimientos = get_data(S3_DM_PROCEDIMIENTOS, "dm_procedimientos.json", "dm_procedimientos.json")

    paciente = next((p for p in pacientes if p.get("patient_id") == patient_id), None)
    if not paciente:
        return jsonify({"error": "Patient not found"}), 404

    return jsonify({
        "paciente":      paciente,
        "escalas":       [r for r in escalas if r.get("patient_id") == patient_id],
        "episodios":     [r for r in episodios if r.get("patient_id") == patient_id],
        "procedimientos": [r for r in procedimientos if r.get("patient_id") == patient_id]
    })


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=False)