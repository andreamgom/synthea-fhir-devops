# tests/test_extractor.py
import pytest
import sys
from pathlib import Path
from unittest.mock import patch

pytestmark = pytest.mark.unit

sys.path.insert(0, str(Path(__file__).parent.parent / "services" / "datamart"))
from extractor import build_dm_paciente, build_dm_funcional, build_dm_episodio, build_dm_procedimientos, build_dm_diagnosticos

MOCK_PATIENTS = [
    {
        "id": "patient-001",
        "gender": "female",
        "birthDate": "1970-01-01",
        "name": [{"use": "official", "family": "García", "given": ["María"]}]
    }
]

MOCK_OBSERVATIONS = [
    {
        "id": "obs-001",
        "subject": {"reference": "Patient/patient-001"},
        "code": {"coding": [{"code": "96761-3", "display": "Barthel index"}]},
        "valueQuantity": {"value": 75},
        "effectiveDateTime": "2024-01-15"
    },
    {
        "id": "obs-002",
        "subject": {"reference": "Patient/patient-001"},
        "code": {"coding": [{"code": "72133-2", "display": "Berg Balance Scale"}]},
        "valueQuantity": {"value": 42},
        "effectiveDateTime": "2024-01-15"
    }
]

MOCK_ENCOUNTERS = [
    {
        "id": "enc-001",
        "subject": {"reference": "Patient/patient-001"},
        "class": {"code": "IMP"},
        "status": "finished",
        "period": {"start": "2024-01-10", "end": "2024-02-10"}
    }
]

MOCK_PROCEDURES = [
    {
        "id": "proc-001",
        "subject": {"reference": "Patient/patient-001"},
        "code": {"coding": [{"code": "36989003", "display": "Physiotherapy"}]},
        "status": "completed",
        "performedDateTime": "2024-01-20"
    }
]

MOCK_CONDITIONS = [
    {
        "id": "cond-001",
        "subject": {"reference": "Patient/patient-001"},
        "code": {"coding": [{"code": "422504002", "display": "Ischemic stroke"}]},
        "onsetDateTime": "2024-01-01",
        "clinicalStatus": {"coding": [{"code": "active"}]}
    }
]


def test_build_dm_paciente_structure():
    dm = build_dm_paciente(MOCK_PATIENTS)
    assert len(dm) == 1
    row = dm[0]
    assert row["patient_id"] == "patient-001"
    assert row["nombre"] == "María"
    assert row["apellido"] == "García"
    assert row["genero"] == "female"


def test_build_dm_funcional_filters_loinc():
    dm = build_dm_funcional(MOCK_OBSERVATIONS)
    assert len(dm) == 2
    codes = [r["loinc_code"] for r in dm]
    assert "96761-3" in codes
    assert "72133-2" in codes


def test_build_dm_funcional_fields():
    dm = build_dm_funcional(MOCK_OBSERVATIONS)
    for row in dm:
        assert "patient_id" in row
        assert "loinc_code" in row
        assert "escala" in row
        assert "valor" in row


def test_build_dm_episodio_structure():
    dm = build_dm_episodio(MOCK_ENCOUNTERS)
    assert len(dm) == 1
    row = dm[0]
    assert row["patient_id"] == "patient-001"
    assert row["encounter_id"] == "enc-001"
    assert row["estado"] == "finished"


def test_build_dm_procedimientos_filters_snomed():
    dm = build_dm_procedimientos(MOCK_PROCEDURES)
    assert len(dm) == 1
    assert dm[0]["procedimiento"] == "Physiotherapy"
    assert dm[0]["snomed_code"] == "36989003"


def test_build_dm_diagnosticos_filters_snomed():
    dm = build_dm_diagnosticos(MOCK_CONDITIONS)
    assert len(dm) == 1
    assert dm[0]["diagnostico"] == "Ischemic stroke"
    assert dm[0]["snomed_code"] == "422504002"
    assert dm[0]["patient_id"] == "patient-001"


def test_build_dm_diagnosticos_ignores_non_neurorehab():
    conditions_no_neuro = [
        {
            "id": "cond-999",
            "subject": {"reference": "Patient/patient-001"},
            "code": {"coding": [{"code": "99999-9", "display": "Other condition"}]},
            "onsetDateTime": "2024-01-01"
        }
    ]
    dm = build_dm_diagnosticos(conditions_no_neuro)
    assert len(dm) == 0


def test_build_dm_funcional_ignores_non_neurorehab():
    obs_no_neuro = [
        {
            "id": "obs-999",
            "subject": {"reference": "Patient/patient-001"},
            "code": {"coding": [{"code": "99999-9", "display": "Other scale"}]},
            "valueQuantity": {"value": 50}
        }
    ]
    dm = build_dm_funcional(obs_no_neuro)
    assert len(dm) == 0


def test_build_dm_paciente_empty():
    dm = build_dm_paciente([])
    assert dm == []