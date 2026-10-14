# terraform/main.tf

terraform {
  required_version = ">= 1.9.0"

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
# Backend remoto — necesario para poder aplicar Terraform desde GitHub
# Actions (el runner es efímero y no conserva el estado local entre
# ejecuciones). Paso único antes de usarlo, ver .github/workflows/terraform-apply.yml.
# backend "s3" {
#   bucket = "synthea-fhir-tfstate-TU-SUFIJO"
#   key    = "terraform.tfstate"
#   region = "us-east-1"
# }

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

module "database" {
  source       = "./modules/database"
  project_name = var.project_name
  environment  = var.environment
  db_password  = var.db_password
  subnet_ids   = var.subnet_ids
  sg_rds_id    = module.networking.sg_rds_id
}

module "compute" {
  source                      = "./modules/compute"
  project_name                = var.project_name
  environment                 = var.environment
  vpc_id                      = var.vpc_id
  subnet_ids                  = var.subnet_ids
  sg_fhir_server_id           = module.networking.sg_fhir_server_id
  sg_backend_services_id      = module.networking.sg_backend_services_id
  sg_query_api_id             = module.networking.sg_query_api_id
  lab_role_arn                = var.lab_role_arn
  rds_endpoint                = module.database.endpoint
  db_password                 = var.db_password
  ecr_fhir_server_url         = module.storage.ecr_fhir_server_url
  ecr_loader_url              = module.storage.ecr_loader_url
  ecr_extractor_url           = module.storage.ecr_extractor_url
  ecr_query_api_url           = module.storage.ecr_query_api_url
  loader_trigger_queue_url    = module.storage.loader_trigger_queue_url
  extractor_trigger_queue_url = module.storage.extractor_trigger_queue_url
  fhir_datalake_bucket        = module.storage.fhir_datalake_bucket_name
  dm_paciente_bucket          = module.storage.dm_paciente_bucket_name
  dm_funcional_bucket         = module.storage.dm_funcional_bucket_name
  dm_episodio_bucket          = module.storage.dm_episodio_bucket_name
  dm_procedimientos_bucket    = module.storage.dm_procedimientos_bucket_name
  dm_diagnosticos_bucket      = module.storage.dm_diagnosticos_bucket_name
}
