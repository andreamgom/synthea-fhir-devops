# services/fhir-server/Dockerfile
FROM hapiproject/hapi:v7.2.0

# Variables de entorno para conectar con RDS PostgreSQL
# Se inyectan en ECS como variables de entorno, no hardcodeadas aquí
ENV spring.datasource.url=""
ENV spring.datasource.username="postgres"
ENV spring.datasource.password=""
ENV spring.datasource.driverClassName="org.postgresql.Driver"
ENV hapi.fhir.fhir_version="R4"

EXPOSE 8080