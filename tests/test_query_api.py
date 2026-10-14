# tests/test_query_api.py
import pytest
import sys
from pathlib import Path
from unittest.mock import patch, MagicMock

pytestmark = pytest.mark.unit

sys.path.insert(0, str(Path(__file__).parent.parent / "services" / "query-api"))

MOCK_PACIENTES = [
    {"patient_id": "001", "nombre": "María", "apellido": "García", "genero": "female", "fecha_nac": "1970-01-01"},
    {"patient_id": "002", "nombre": "Juan", "apellido": "López", "genero": "male", "fecha_nac": "1965-05-15"}
]

MOCK_DIAGNOSTICOS = [
    {"patient_id": "001", "diagnostico": "Ischemic stroke", "snomed_code": "422504002", "fecha_inicio": "2024-01-01", "estado": "active"}
]

MOCK_ESCALAS = [
    {"patient_id": "001", "escala": "Barthel index", "loinc_code": "96761-3", "valor": 75, "fecha": "2024-01-15"},
    {"patient_id": "001", "escala": "Berg Balance Scale", "loinc_code": "72133-2", "valor": 42, "fecha": "2024-01-15"}
]


def get_mock_app():
    with patch.dict('os.environ', {
        'S3_DM_PACIENTE': '',
        'S3_DM_FUNCIONAL': '',
        'S3_DM_EPISODIO': '',
        'S3_DM_PROCEDIMIENTOS': '',
        'S3_DM_DIAGNOSTICOS': ''
    }):
        import app
        app.app.config['TESTING'] = True
        return app.app.test_client(), app


def test_health_endpoint():
    client, _ = get_mock_app()
    response = client.get('/health')
    assert response.status_code == 200
    data = response.get_json()
    assert data['status'] == 'ok'


def test_pacientes_endpoint():
    client, app_module = get_mock_app()
    with patch.object(app_module, 'get_data', return_value=MOCK_PACIENTES):
        response = client.get('/api/pacientes')
        assert response.status_code == 200
        data = response.get_json()
        assert data['total'] == 2
        assert len(data['data']) == 2


def test_diagnosticos_endpoint():
    client, app_module = get_mock_app()
    with patch.object(app_module, 'get_data', return_value=MOCK_DIAGNOSTICOS):
        response = client.get('/api/diagnosticos')
        assert response.status_code == 200
        data = response.get_json()
        assert data['total'] == 1
        assert data['data'][0]['diagnostico'] == 'Ischemic stroke'


def test_escalas_endpoint():
    client, app_module = get_mock_app()
    with patch.object(app_module, 'get_data', return_value=MOCK_ESCALAS):
        response = client.get('/api/escalas')
        assert response.status_code == 200
        data = response.get_json()
        assert data['total'] == 2


def test_paciente_not_found():
    client, app_module = get_mock_app()
    with patch.object(app_module, 'get_data', return_value=[]):
        response = client.get('/api/pacientes/999/resumen')
        assert response.status_code == 404