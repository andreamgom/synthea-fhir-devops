# terraform/modules/storage/main.tf

locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

resource "random_id" "suffix" {
  byte_length = 4
}

# ── FHIR DATALAKE ─────────────────────────────────────────────────────
resource "aws_s3_bucket" "fhir_datalake" {
  bucket        = "${local.name_prefix}-fhir-datalake-${random_id.suffix.hex}"
  force_destroy = true
  tags          = { Name = "${local.name_prefix}-fhir-datalake" }
}

resource "aws_s3_bucket_public_access_block" "fhir_datalake" {
  bucket                  = aws_s3_bucket.fhir_datalake.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_object" "raw_fhir" {
  bucket  = aws_s3_bucket.fhir_datalake.id
  key     = "raw/fhir/"
  content = ""
}

# ── DATAMART PACIENTE ─────────────────────────────────────────────────
resource "aws_s3_bucket" "dm_paciente" {
  bucket        = "${local.name_prefix}-dm-paciente-${random_id.suffix.hex}"
  force_destroy = true
  tags          = { Name = "${local.name_prefix}-dm-paciente" }
}

resource "aws_s3_bucket_public_access_block" "dm_paciente" {
  bucket                  = aws_s3_bucket.dm_paciente.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ── DATAMART FUNCIONAL ────────────────────────────────────────────────
resource "aws_s3_bucket" "dm_funcional" {
  bucket        = "${local.name_prefix}-dm-funcional-${random_id.suffix.hex}"
  force_destroy = true
  tags          = { Name = "${local.name_prefix}-dm-funcional" }
}

resource "aws_s3_bucket_public_access_block" "dm_funcional" {
  bucket                  = aws_s3_bucket.dm_funcional.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ── DATAMART EPISODIO ─────────────────────────────────────────────────
resource "aws_s3_bucket" "dm_episodio" {
  bucket        = "${local.name_prefix}-dm-episodio-${random_id.suffix.hex}"
  force_destroy = true
  tags          = { Name = "${local.name_prefix}-dm-episodio" }
}

resource "aws_s3_bucket_public_access_block" "dm_episodio" {
  bucket                  = aws_s3_bucket.dm_episodio.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ── DATAMART PROCEDIMIENTOS ───────────────────────────────────────────
resource "aws_s3_bucket" "dm_procedimientos" {
  bucket        = "${local.name_prefix}-dm-procedimientos-${random_id.suffix.hex}"
  force_destroy = true
  tags          = { Name = "${local.name_prefix}-dm-procedimientos" }
}

resource "aws_s3_bucket_public_access_block" "dm_procedimientos" {
  bucket                  = aws_s3_bucket.dm_procedimientos.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ── ECR ───────────────────────────────────────────────────────────────
resource "aws_ecr_repository" "fhir_server" {
  name                 = "${local.name_prefix}-fhir-server"
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration { scan_on_push = true }
  tags = { Name = "${local.name_prefix}-fhir-server" }
}

resource "aws_ecr_repository" "loader" {
  name                 = "${local.name_prefix}-loader"
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration { scan_on_push = true }
  tags = { Name = "${local.name_prefix}-loader" }
}

resource "aws_ecr_repository" "extractor" {
  name                 = "${local.name_prefix}-extractor"
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration { scan_on_push = true }
  tags = { Name = "${local.name_prefix}-extractor" }
}

resource "aws_ecr_repository" "query_api" {
  name                 = "${local.name_prefix}-query-api"
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration { scan_on_push = true }
  tags = { Name = "${local.name_prefix}-query-api" }
}