# terraform/modules/storage/main.tf

locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

# ── S3 DATALAKE ───────────────────────────────────────────────────────
resource "aws_s3_bucket" "datalake" {
  # Los nombres de S3 son globales — añadimos sufijo aleatorio para evitar colisiones
  bucket        = "${local.name_prefix}-datalake-${random_id.suffix.hex}"
  force_destroy = true # permite destruir aunque tenga objetos (útil en dev)

  tags = { Name = "${local.name_prefix}-datalake" }
}

resource "random_id" "suffix" {
  byte_length = 4
}

# Bloquear acceso público al bucket
resource "aws_s3_bucket_public_access_block" "datalake" {
  bucket = aws_s3_bucket.datalake.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Estructura de prefijos del datalake (objetos vacíos que actúan como carpetas)
resource "aws_s3_object" "raw_fhir" {
  bucket  = aws_s3_bucket.datalake.id
  key     = "raw/fhir/"
  content = ""
}

resource "aws_s3_object" "processed" {
  bucket  = aws_s3_bucket.datalake.id
  key     = "processed/"
  content = ""
}

resource "aws_s3_object" "datamarts" {
  bucket  = aws_s3_bucket.datalake.id
  key     = "datamarts/"
  content = ""
}

# ── ECR — registro de imágenes Docker ────────────────────────────────
resource "aws_ecr_repository" "fhir_server" {
  name                 = "${local.name_prefix}-fhir-server"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true # escaneo de vulnerabilidades automático
  }

  tags = { Name = "${local.name_prefix}-fhir-server" }
}

resource "aws_ecr_repository" "loader" {
  name                 = "${local.name_prefix}-loader"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = { Name = "${local.name_prefix}-loader" }
}