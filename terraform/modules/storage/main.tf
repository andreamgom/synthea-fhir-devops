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

# ── DATAMART DIAGNOSTICOS ─────────────────────────────────────────────
resource "aws_s3_bucket" "dm_diagnosticos" {
  bucket        = "${local.name_prefix}-dm-diagnosticos-${random_id.suffix.hex}"
  force_destroy = true
  tags          = { Name = "${local.name_prefix}-dm-diagnosticos" }
}

resource "aws_s3_bucket_public_access_block" "dm_diagnosticos" {
  bucket                  = aws_s3_bucket.dm_diagnosticos.id
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

# ── SQS — PIPELINE ASÍNCRONO DATALAKE → LOADER → EXTRACTOR ─────────────
#
# loader-trigger-queue: recibe un mensaje por cada objeto nuevo subido al
# datalake (raw/fhir/*.json) vía notificación de eventos de S3. El loader
# hace long-polling sobre esta cola.
#
# extractor-trigger-queue: el propio loader publica en esta cola cuando
# termina de cargar un bundle correctamente. El extractor hace long-polling
# sobre esta cola y, al recibir un mensaje, relanza la extracción completa
# de los datamarts.

resource "aws_sqs_queue" "loader_trigger" {
  name                       = "${local.name_prefix}-loader-trigger-queue"
  visibility_timeout_seconds = 600
  message_retention_seconds  = 86400
  receive_wait_time_seconds  = 20 # long polling

  tags = { Name = "${local.name_prefix}-loader-trigger-queue" }
}

resource "aws_sqs_queue" "extractor_trigger" {
  name                       = "${local.name_prefix}-extractor-trigger-queue"
  visibility_timeout_seconds = 300
  message_retention_seconds  = 86400
  receive_wait_time_seconds  = 20 # long polling

  tags = { Name = "${local.name_prefix}-extractor-trigger-queue" }
}

# Permite que el servicio S3 publique en loader-trigger-queue, restringido
# al bucket del datalake mediante la condición aws:SourceArn.
resource "aws_sqs_queue_policy" "loader_trigger" {
  queue_url = aws_sqs_queue.loader_trigger.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowS3SendMessage"
        Effect    = "Allow"
        Principal = { Service = "s3.amazonaws.com" }
        Action    = "sqs:SendMessage"
        Resource  = aws_sqs_queue.loader_trigger.arn
        Condition = {
          ArnEquals = { "aws:SourceArn" = aws_s3_bucket.fhir_datalake.arn }
        }
      }
    ]
  })
}

# Notificación de eventos del bucket datalake → loader-trigger-queue,
# solo para objetos nuevos bajo raw/fhir/ con extensión .json.
resource "aws_s3_bucket_notification" "fhir_datalake" {
  bucket = aws_s3_bucket.fhir_datalake.id

  queue {
    queue_arn     = aws_sqs_queue.loader_trigger.arn
    events        = ["s3:ObjectCreated:*"]
    filter_prefix = "raw/fhir/"
    filter_suffix = ".json"
  }

  depends_on = [aws_sqs_queue_policy.loader_trigger]
}
