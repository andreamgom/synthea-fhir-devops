# Loader Synthea -> HAPI FHIR

Este componente carga bundles FHIR generados por Synthea en el servidor HAPI FHIR local.

## Orden de carga

1. hospitalInformation*.json
2. practitionerInformation*.json
3. bundles de pacientes

## Ejecución manual

Desde la raíz del repositorio:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\run-local-pipeline.ps1 -Population 5
```

## Requisitos

- HAPI FHIR levantado en http://localhost:8080/fhir/
- Synthea clonado en `services/synthea`
- Java instalado y accesible