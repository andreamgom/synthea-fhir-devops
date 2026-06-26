# terraform/modules/compute/variables.tf

variable "project_name" { type = string }
variable "environment"  { type = string }

variable "vpc_id"            { type = string }
variable "subnet_ids"        { type = list(string) }
variable "sg_fhir_server_id" { type = string }
variable "lab_role_arn"      { type = string }

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