# terraform/outputs.tf

output "aws_region" {
  description = "Región AWS usada"
  value       = var.aws_region
}

output "lab_role_arn" {
  description = "ARN del LabRole usado para ECS tasks en Academy"
  value       = var.lab_role_arn
}

# output "github_actions_access_key_id" {
#   value     = module.iam.github_actions_access_key_id
#   sensitive = true
# }

# output "github_actions_secret_access_key" {
#   value     = module.iam.github_actions_secret_access_key
#   sensitive = true
# }


# Se irán añadiendo outputs de cada módulo conforme se creen:
# output "vpc_id"             { value = module.networking.vpc_id }
# output "s3_datalake_bucket" { value = module.storage.bucket_name }
# output "ecs_cluster_name"   { value = module.compute.cluster_name }
# output "rds_endpoint"       { value = module.database.endpoint }