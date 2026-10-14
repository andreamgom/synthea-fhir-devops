# terraform/modules/compute/variables.tf

variable "project_name" { type = string }
variable "environment" { type = string }

variable "vpc_id" { type = string }
variable "subnet_ids" { type = list(string) }
variable "sg_fhir_server_id" { type = string }
variable "sg_backend_services_id" {
  description = "SG de salida usada por loader y extractor"
  type        = string
}
variable "sg_query_api_id" {
  description = "SG de entrada usado por query-api (puerto 5000)"
  type        = string
}
variable "lab_role_arn" { type = string }

variable "rds_endpoint" {
  description = "Endpoint RDS para inyectar en HAPI FHIR como variable de entorno"
  type        = string
}

variable "db_password" {
  type      = string
  sensitive = true
}

variable "ecr_fhir_server_url" {
  description = "URL del repositorio ECR de HAPI FHIR"
  type        = string
}

variable "ecr_loader_url" {
  description = "URL del repositorio ECR del loader"
  type        = string
}

variable "ecr_extractor_url" {
  description = "URL del repositorio ECR del extractor"
  type        = string
}

variable "ecr_query_api_url" {
  description = "URL del repositorio ECR de la query-api"
  type        = string
}

variable "loader_trigger_queue_url" {
  description = "URL de la cola SQS que dispara el loader (eventos S3 del datalake)"
  type        = string
}

variable "extractor_trigger_queue_url" {
  description = "URL de la cola SQS que dispara el extractor (publicada por el loader)"
  type        = string
}

variable "fhir_datalake_bucket" {
  description = "Bucket S3 del datalake FHIR — usado por el loader"
  type        = string
}

variable "dm_paciente_bucket" { type = string }
variable "dm_funcional_bucket" { type = string }
variable "dm_episodio_bucket" { type = string }
variable "dm_procedimientos_bucket" { type = string }
variable "dm_diagnosticos_bucket" { type = string }
