# tests/test_fhir_integration.py
import requests
import pytest

pytestmark = pytest.mark.integration


HEADERS = {"Accept": "application/fhir+json"}


def test_fhir_metadata(fhir_url):
    """HAPI FHIR debe responder con un CapabilityStatement."""
    response = requests.get(f"{fhir_url}/metadata", headers=HEADERS, timeout=30)
    assert response.status_code == 200
    data = response.json()
    assert data["resourceType"] == "CapabilityStatement"
    assert data["fhirVersion"] == "4.0.1"


def test_fhir_patient_endpoint(fhir_url):
    """El endpoint de pacientes debe responder con un Bundle."""
    response = requests.get(f"{fhir_url}/Patient", headers=HEADERS, timeout=30)
    assert response.status_code == 200
    data = response.json()
    assert data["resourceType"] == "Bundle"


def test_fhir_observation_endpoint(fhir_url):
    """El endpoint de observaciones debe responder con un Bundle."""
    response = requests.get(f"{fhir_url}/Observation", headers=HEADERS, timeout=30)
    assert response.status_code == 200
    data = response.json()
    assert data["resourceType"] == "Bundle"


def test_fhir_condition_endpoint(fhir_url):
    """El endpoint de condiciones debe responder con un Bundle."""
    response = requests.get(f"{fhir_url}/Condition", headers=HEADERS, timeout=30)
    assert response.status_code == 200
    data = response.json()
    assert data["resourceType"] == "Bundle"


def test_fhir_has_patients(fhir_url):
    """Debe haber al menos un paciente cargado."""
    response = requests.get(
        f"{fhir_url}/Patient?_summary=count",
        headers=HEADERS,
        timeout=30
    )
    assert response.status_code == 200
    data = response.json()
    assert data.get("total", 0) > 0


def test_fhir_neurorehab_scales(fhir_url):
    """Debe haber observaciones con códigos LOINC de neurorrehabilitación."""
    loinc_codes = ["96761-3", "72133-2", "83243-2"]
    for code in loinc_codes:
        response = requests.get(
            f"{fhir_url}/Observation?code={code}&_summary=count",
            headers=HEADERS,
            timeout=30
        )
        assert response.status_code == 200