# terraform/modules/networking/main.tf
# AWS Academy no permite operaciones EC2 de red — VPC y subnets se pasan como variables

locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

resource "aws_security_group" "fhir_server" {
  name        = "${local.name_prefix}-sg-fhir"
  description = "Acceso al servidor HAPI FHIR"
  vpc_id      = var.vpc_id

  # HAPI no tiene autenticacion y tiene $expunge activo: solo se permite el acceso
  # desde los servicios backend (loader y extractor), nunca desde internet.
  ingress {
    description     = "FHIR HTTP desde loader y extractor"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.backend_services.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name_prefix}-sg-fhir" }
}

resource "aws_security_group" "rds" {
  name        = "${local.name_prefix}-sg-rds"
  description = "Acceso a RDS solo desde el SG de FHIR"
  vpc_id      = var.vpc_id

  ingress {
    description     = "PostgreSQL desde FHIR server"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.fhir_server.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name_prefix}-sg-rds" }
}

# SG para loader/extractor — servicios backend que consumen de SQS y llaman
# a FHIR/S3 vía salida a internet, pero no exponen ningún puerto de entrada.
resource "aws_security_group" "backend_services" {
  name        = "${local.name_prefix}-sg-backend"
  description = "Acceso saliente para loader y extractor (SQS, S3, FHIR)"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name_prefix}-sg-backend" }
}

# SG para query-api — expone la API REST de consulta de los datamarts
resource "aws_security_group" "query_api" {
  name        = "${local.name_prefix}-sg-query-api"
  description = "Acceso a la Neurorehab Query API"
  vpc_id      = var.vpc_id

  ingress {
    description = "Query API HTTP"
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name_prefix}-sg-query-api" }
}
