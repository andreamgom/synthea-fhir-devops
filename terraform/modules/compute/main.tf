# terraform/modules/compute/main.tf

locals {
  name_prefix = "${var.project_name}-${var.environment}"
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

# ── CLOUDWATCH LOG GROUP ──────────────────────────────────────────────
resource "aws_cloudwatch_log_group" "fhir_server" {
  name              = "/ecs/${local.name_prefix}-fhir-server"
  retention_in_days = 7

  tags = { Name = "${local.name_prefix}-fhir-logs" }
}

# ── TASK DEFINITION — HAPI FHIR ──────────────────────────────────────
resource "aws_ecs_task_definition" "fhir_server" {
  family                   = "${local.name_prefix}-fhir-server"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "512"
  memory                   = "1024"

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
        },
        {
          name  = "spring.jpa.hibernate.ddl-auto"
          value = "update"
        },
        {
          name  = "spring.jpa.properties.hibernate.hbm2ddl.auto"
          value = "update"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.fhir_server.name
          "awslogs-region"        = "us-east-1"
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