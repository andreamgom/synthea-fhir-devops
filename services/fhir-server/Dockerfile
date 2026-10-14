# services/fhir-server/Dockerfile
# La imagen pública de HAPI FHIR se usa tal cual, pero el pipeline de
# despliegue (deploy.yml) construye y publica cada servicio en el ECR
# privado del proyecto, así que necesitamos este Dockerfile aunque solo
# envuelva la imagen oficial, en vez de hacer el "docker build" directamente
# contra hapiproject/hapi.
FROM hapiproject/hapi:v7.2.0

# Con la base de datos PostgreSQL de RDS, HAPI debe usar su dialecto de
# PostgreSQL; con el dialecto por defecto (H2) no crea sus tablas
# (error: relation "bt2_job_instance" does not exist).
ENV SPRING_JPA_PROPERTIES_HIBERNATE_DIALECT=ca.uhn.fhir.jpa.model.dialect.HapiFhirPostgresDialect

# Variable oficial de la imagen HAPI (docker-compose del proyecto HAPI) para
# cambiar el dialecto de Hibernate.
ENV HIBERNATE_DIALECT=ca.uhn.fhir.jpa.model.dialect.HapiFhirPostgresDialect

ENV JAVA_TOOL_OPTIONS="-XX:MaxRAMPercentage=75.0 -Dhapi.fhir.expunge_enabled=true -Dhapi.fhir.allow_multiple_delete=true -Dspring.jpa.properties.hibernate.dialect=ca.uhn.fhir.jpa.model.dialect.HapiFhirPostgresDialect -Dhibernate.dialect=ca.uhn.fhir.jpa.model.dialect.HapiFhirPostgresDialect"
