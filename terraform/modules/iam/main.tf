# terraform/modules/iam/main.tf

locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

# ── ROL PARA ECS TASKS ────────────────────────────────────────────────
# Permite que los contenedores en ECS accedan a S3 y ECR

resource "aws_iam_role" "ecs_task_execution" {
  name = "${local.name_prefix}-ecs-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Name = "${local.name_prefix}-ecs-execution-role" }
}

# Policy gestionada por AWS para ECS — permite pull de ECR y logs en CloudWatch
resource "aws_iam_role_policy_attachment" "ecs_execution_managed" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ── ROL PARA LAS TASKS (permisos de aplicación) ───────────────────────
# Separado del execution role — este es el que usa el código dentro del contenedor

resource "aws_iam_role" "ecs_task" {
  name = "${local.name_prefix}-ecs-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Name = "${local.name_prefix}-ecs-task-role" }
}

# Policy custom — acceso al datalake S3
resource "aws_iam_role_policy" "ecs_task_s3" {
  name = "${local.name_prefix}-ecs-s3-policy"
  role = aws_iam_role.ecs_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          var.datalake_bucket_arn,
          "${var.datalake_bucket_arn}/*"
        ]
      }
    ]
  })
}

# ── ROL PARA GITHUB ACTIONS ───────────────────────────────────────────
# Credenciales estáticas temporales — Academy no soporta OIDC
# En producción real se usaría OIDC (sin credenciales estáticas)

resource "aws_iam_user" "github_actions" {
  name = "${local.name_prefix}-github-actions"
  tags = { Name = "${local.name_prefix}-github-actions" }
}

resource "aws_iam_user_policy" "github_actions" {
  name = "${local.name_prefix}-github-actions-policy"
  user = aws_iam_user.github_actions.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecs:UpdateService",
          "ecs:DescribeServices",
          "ecs:DescribeTaskDefinition",
          "ecs:RegisterTaskDefinition"
        ]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:GetObject", "s3:ListBucket"]
        Resource = [
          var.datalake_bucket_arn,
          "${var.datalake_bucket_arn}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_access_key" "github_actions" {
  user = aws_iam_user.github_actions.name
}