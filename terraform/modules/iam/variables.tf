# terraform/modules/iam/variables.tf

variable "project_name"        { type = string }
variable "environment"         { type = string }
variable "datalake_bucket_arn" { type = string }