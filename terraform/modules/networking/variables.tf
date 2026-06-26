variable "project_name" { type = string }
variable "environment" { type = string }
variable "region" { type = string }

variable "vpc_id" {
  description = "ID de la VPC por defecto de AWS Academy (se obtiene manualmente)"
  type        = string
}

variable "subnet_ids" {
  description = "IDs de subnets disponibles en la VPC de Academy"
  type        = list(string)
}