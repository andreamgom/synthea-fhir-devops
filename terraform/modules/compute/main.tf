# terraform/modules/compute/main.tf

locals {
  name_prefix    = "${var.project_name}-${var.environment}"
  aws_log_region = "us-east-1"
}

# ── ECS CLUSTER ───────────────────────────────────────────────────────
resource "aws_ecs_cluster" "main" {
  name = "${local.name_prefix}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = { Name = "${local.name_prefix}-cluster" }
}

# ── CLOUDWATCH LOG GROUPS ─────────────────────────────────────────────
resource "aws_cloudwatch_log_group" "fhir_server" {
  name              = "/ecs/${local.name_prefix}-fhir-server"
  retention_in_days = 7

  tags = { Name = "${local.name_prefix}-fhir-logs" }
}

resource "aws_cloudwatch_log_group" "loader" {
  name              = "/ecs/${local.name_prefix}-loader"
  retention_in_days = 7

  tags = { Name = "${local.name_prefix}-loader-logs" }
}

resource "aws_cloudwatch_log_group" "extractor" {
  name              = "/ecs/${local.name_prefix}-extractor"
  retention_in_days = 7

  tags = { Name = "${local.name_prefix}-extractor-logs" }
}

resource "aws_cloudwatch_log_group" "query_api" {
  name              = "/ecs/${local.name_prefix}-query-api"
  retention_in_days = 7

  tags = { Name = "${local.name_prefix}-query-api-logs" }
}

# ── TASK DEFINITION — HAPI FHIR ──────────────────────────────────────
resource "aws_ecs_task_definition" "fhir_server" {
  family                   = "${local.name_prefix}-fhir-server"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "1024"
  memory                   = "4096"

  # LabRole sustituye a los roles IAM custom que Academy no permite crear
  execution_role_arn = var.lab_role_arn
  task_role_arn      = var.lab_role_arn

  container_definitions = jsonencode([
    {
      name  = "hapi-fhir"
      image = "${var.ecr_fhir_server_url}:latest"

      portMappings = [
        {
          containerPort = 8080
          protocol      = "tcp"
        }
      ]

      environment = [
        {
          name  = "spring.datasource.url"
          value = "jdbc:postgresql://${var.rds_endpoint}/hapifhir"
        },
        {
          name  = "spring.datasource.username"
          value = "postgres"
        },
        {
          name  = "spring.datasource.password"
          value = var.db_password
        },
        {
          name  = "spring.datasource.driverClassName"
          value = "org.postgresql.Driver"
        },
        {
          name  = "hapi.fhir.fhir_version"
          value = "R4"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.fhir_server.name
          "awslogs-region"        = local.aws_log_region
          "awslogs-stream-prefix" = "fhir"
        }
      }

      essential = true
    }
  ])

  tags = { Name = "${local.name_prefix}-fhir-task" }
}

# ── ECS SERVICE — HAPI FHIR ───────────────────────────────────────────
resource "aws_ecs_service" "fhir_server" {
  name            = "${local.name_prefix}-fhir-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.fhir_server.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [var.sg_fhir_server_id]
    assign_public_ip = true
  }

  # Permite actualizar la task definition sin recrear el servicio
  force_new_deployment = true

  tags = { Name = "${local.name_prefix}-fhir-service" }
}

# ── TASK DEFINITION — LOADER ─────────────────────────────────────────
# Consumidor SQS long-polling: se dispara con cada objeto nuevo subido al
# datalake (raw/fhir/*.json) vía loader-trigger-queue, y al terminar de
# cargar un bundle publica en extractor-trigger-queue.
resource "aws_ecs_task_definition" "loader" {
  family                   = "${local.name_prefix}-loader"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"

  execution_role_arn = var.lab_role_arn
  task_role_arn      = var.lab_role_arn

  container_definitions = jsonencode([
    {
      name  = "loader"
      image = "${var.ecr_loader_url}:latest"

      environment = [
        # AWS Academy bloquea Cloud Map (servicediscovery:*), así que el
        # servicio localiza la IP privada de HAPI FHIR consultando a ECS.
        { name = "FHIR_ECS_CLUSTER", value = aws_ecs_cluster.main.name },
        { name = "FHIR_ECS_SERVICE", value = aws_ecs_service.fhir_server.name },
        { name = "FHIR_PORT", value = "8080" },
        { name = "S3_BUCKET", value = var.fhir_datalake_bucket },
        { name = "S3_PREFIX", value = "raw/fhir/" },
        { name = "AWS_REGION", value = local.aws_log_region },
        { name = "LOADER_TRIGGER_QUEUE_URL", value = var.loader_trigger_queue_url },
        { name = "EXTRACTOR_TRIGGER_QUEUE_URL", value = var.extractor_trigger_queue_url },
        { name = "RUN_MODE", value = "sqs" }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.loader.name
          "awslogs-region"        = local.aws_log_region
          "awslogs-stream-prefix" = "loader"
        }
      }

      essential = true
    }
  ])

  tags = { Name = "${local.name_prefix}-loader-task" }
}

resource "aws_ecs_service" "loader" {
  name            = "${local.name_prefix}-loader-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.loader.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [var.sg_backend_services_id]
    assign_public_ip = true
  }

  force_new_deployment = true

  tags = { Name = "${local.name_prefix}-loader-service" }
}

# ── TASK DEFINITION — EXTRACTOR ──────────────────────────────────────
# Consumidor SQS long-polling: se dispara con los mensajes que publica el
# loader en extractor-trigger-queue al completar una carga, y relanza la
# extracción completa de los datamarts.
resource "aws_ecs_task_definition" "extractor" {
  family                   = "${local.name_prefix}-extractor"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"

  execution_role_arn = var.lab_role_arn
  task_role_arn      = var.lab_role_arn

  container_definitions = jsonencode([
    {
      name  = "extractor"
      image = "${var.ecr_extractor_url}:latest"

      environment = [
        # AWS Academy bloquea Cloud Map (servicediscovery:*), así que el
        # servicio localiza la IP privada de HAPI FHIR consultando a ECS.
        { name = "FHIR_ECS_CLUSTER", value = aws_ecs_cluster.main.name },
        { name = "FHIR_ECS_SERVICE", value = aws_ecs_service.fhir_server.name },
        { name = "FHIR_PORT", value = "8080" },
        { name = "AWS_REGION", value = local.aws_log_region },
        { name = "EXTRACTOR_TRIGGER_QUEUE_URL", value = var.extractor_trigger_queue_url },
        { name = "RUN_MODE", value = "sqs" },
        { name = "S3_DM_PACIENTE", value = var.dm_paciente_bucket },
        { name = "S3_DM_FUNCIONAL", value = var.dm_funcional_bucket },
        { name = "S3_DM_EPISODIO", value = var.dm_episodio_bucket },
        { name = "S3_DM_PROCEDIMIENTOS", value = var.dm_procedimientos_bucket },
        { name = "S3_DM_DIAGNOSTICOS", value = var.dm_diagnosticos_bucket }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.extractor.name
          "awslogs-region"        = local.aws_log_region
          "awslogs-stream-prefix" = "extractor"
        }
      }

      essential = true
    }
  ])

  tags = { Name = "${local.name_prefix}-extractor-task" }
}

resource "aws_ecs_service" "extractor" {
  name            = "${local.name_prefix}-extractor-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.extractor.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [var.sg_backend_services_id]
    assign_public_ip = true
  }

  force_new_deployment = true

  tags = { Name = "${local.name_prefix}-extractor-service" }
}

# ── TASK DEFINITION — QUERY API ──────────────────────────────────────
# API REST (Flask) que expone los cinco datamarts generados por el
# extractor, con fallback a ficheros locales cuando S3 no está disponible.
resource "aws_ecs_task_definition" "query_api" {
  family                   = "${local.name_prefix}-query-api"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"

  execution_role_arn = var.lab_role_arn
  task_role_arn      = var.lab_role_arn

  container_definitions = jsonencode([
    {
      name  = "query-api"
      image = "${var.ecr_query_api_url}:latest"

      portMappings = [
        {
          containerPort = 5000
          protocol      = "tcp"
        }
      ]

      environment = [
        { name = "AWS_REGION", value = local.aws_log_region },
        { name = "S3_DM_PACIENTE", value = var.dm_paciente_bucket },
        { name = "S3_DM_FUNCIONAL", value = var.dm_funcional_bucket },
        { name = "S3_DM_EPISODIO", value = var.dm_episodio_bucket },
        { name = "S3_DM_PROCEDIMIENTOS", value = var.dm_procedimientos_bucket },
        { name = "S3_DM_DIAGNOSTICOS", value = var.dm_diagnosticos_bucket }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.query_api.name
          "awslogs-region"        = local.aws_log_region
          "awslogs-stream-prefix" = "query-api"
        }
      }

      essential = true
    }
  ])

  tags = { Name = "${local.name_prefix}-query-api-task" }
}

resource "aws_ecs_service" "query_api" {
  name            = "${local.name_prefix}-query-api-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.query_api.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [var.sg_query_api_id]
    assign_public_ip = true
  }

  force_new_deployment = true

  tags = { Name = "${local.name_prefix}-query-api-service" }
}
