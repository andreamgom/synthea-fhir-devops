# terraform/variables.tf

variable "aws_region" {
  description = "Región AWS donde se despliega la infra"
  type        = string
  default     = "eu-west-1"  # Irlanda — la más cercana a España con Free Tier completo
}

variable "project_name" {
  description = "Nombre del proyecto, usado como prefijo en todos los recursos"
  type        = string
  default     = "synthea-fhir"
}

variable "environment" {
  description = "Entorno de despliegue"
  type        = string
  default     = "dev"
}

variable "db_password" {
  description = "Contraseña del usuario postgres en RDS — se inyecta desde tfvars o variable de entorno"
  type        = string
  sensitive   = true
}

variable "vpc_id" {
  description = "ID de la VPC por defecto de AWS Academy"
  type        = string
}

variable "subnet_ids" {
  description = "IDs de subnets de AWS Academy"
  type        = list(string)
}

variable "lab_role_arn" {
  description = "ARN del rol LabRole de AWS Academy — sustituye a los roles IAM custom"
  type        = string
  default     = "arn:aws:iam::964584584741:role/LabRole"
}