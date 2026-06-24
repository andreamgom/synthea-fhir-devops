# terraform/outputs.tf

output "aws_region" {
  description = "Región AWS usada"
  value       = var.aws_region
}

# Se irán añadiendo outputs de cada módulo conforme se creen:
# output "vpc_id"             { value = module.networking.vpc_id }
# output "s3_datalake_bucket" { value = module.storage.bucket_name }
# output "ecs_cluster_name"   { value = module.compute.cluster_name }
# output "rds_endpoint"       { value = module.database.endpoint }