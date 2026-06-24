# terraform/main.tf

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}
  # Backend local por ahora — en el Paso 3 (CI/CD) lo moveremos a S3
  # backend "s3" { ... }

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

# ──────────────────────────────────────────
# MÓDULOS — se irán descomentando conforme
# se creen los archivos de cada módulo
# ──────────────────────────────────────────

module "networking" {
  source       = "./modules/networking"
  project_name = var.project_name
  environment  = var.environment
  region       = var.aws_region
  vpc_id       = var.vpc_id
  subnet_ids   = var.subnet_ids
}

module "storage" {
  source       = "./modules/storage"
  project_name = var.project_name
  environment  = var.environment
}

# module "iam" {
#   source              = "./modules/iam"
#   project_name        = var.project_name
#   environment         = var.environment
#   datalake_bucket_arn = module.storage.datalake_bucket_arn
# }

# module "database" {
#   source          = "./modules/database"
#   project_name    = var.project_name
#   environment     = var.environment
#   db_password     = var.db_password
#   vpc_id          = module.networking.vpc_id
#   private_subnets = module.networking.private_subnet_ids
# }

# module "compute" {
#   source       = "./modules/compute"
#   project_name = var.project_name
#   environment  = var.environment
#   vpc_id       = module.networking.vpc_id
# }