# terraform/modules/networking/main.tf
# AWS Academy no permite operaciones EC2 de red — VPC y subnets se pasan como variables

locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

resource "aws_security_group" "fhir_server" {
  name        = "${local.name_prefix}-sg-fhir"
  description = "Acceso al servidor HAPI FHIR"
  vpc_id      = var.vpc_id

  ingress {
    description = "FHIR HTTP"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
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