# tests/test_extractor.py
import sys
import os
import json
import pytest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "services" / "datamart"))
from extractor import fetch_all, build_dm_paciente, build_dm_funcional, build_dm_episodio


def test_fetch_patients(fhir_url):
    """Debe poder obtener pacientes de HAPI FHIR."""
    os.environ["FHIR_SERVER_URL"] = fhir_url
    patients = fetch_all("Patient")
    assert isinstance(patients, list)
    assert len(patients) > 0


def test_build_dm_paciente(fhir_url):
    """dm_paciente debe tener los campos correctos."""
    os.environ["FHIR_SERVER_URL"] = fhir_url
    patients = fetch_all("Patient")
    dm = build_dm_paciente(patients)
    assert len(dm) > 0
    for row in dm:
        assert "patient_id" in row
        assert "nombre" in row
        assert "apellido" in row
        assert "genero" in row


def test_build_dm_funcional(fhir_url):
    """dm_funcional debe contener escalas clínicas de neurorrehabilitación."""
    os.environ["FHIR_SERVER_URL"] = fhir_url
    observations = fetch_all("Observation")
    dm = build_dm_funcional(observations)
    assert isinstance(dm, list)
    if len(dm) > 0:
        for row in dm:
            assert "patient_id" in row
            assert "loinc_code" in row
            assert "escala" in row
            assert "valor" in row


def test_build_dm_episodio(fhir_url):
    """dm_episodio debe contener episodios con fechas."""
    os.environ["FHIR_SERVER_URL"] = fhir_url
    encounters = fetch_all("Encounter")
    dm = build_dm_episodio(encounters)
    assert isinstance(dm, list)
    assert len(dm) > 0
    for row in dm:
        assert "patient_id" in row
        assert "encounter_id" in row
        assert "estado" in row