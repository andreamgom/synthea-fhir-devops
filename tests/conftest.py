# tests/conftest.py
import pytest
import os

@pytest.fixture
def fhir_url():
    return os.getenv("FHIR_SERVER_URL", "http://localhost:8080/fhir")

@pytest.fixture
def s3_bucket():
    return os.getenv("S3_BUCKET", "synthea-fhir-dev-datalake-547c2ee6")