# terraform/modules/database/variables.tf

variable "project_name" { type = string }
variable "environment" { type = string }

variable "db_password" {
  type      = string
  sensitive = true
}

variable "subnet_ids" {
  description = "Subnets donde se desplegará RDS"
  type        = list(string)
}

variable "sg_rds_id" {
  description = "Security Group para RDS"
  type        = string
}