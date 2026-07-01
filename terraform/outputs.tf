# terraform/outputs.tf

output "aws_region" {
  value = var.aws_region
}

output "lab_role_arn" {
  value = var.lab_role_arn
}

output "rds_endpoint" {
  value = module.database.endpoint
}

output "ecs_cluster_name" {
  value = module.compute.ecs_cluster_name
}

output "fhir_task_definition_arn" {
  value = module.compute.fhir_task_definition_arn
}

output "fhir_datalake_bucket" {
  value = module.storage.fhir_datalake_bucket_name
}

output "dm_paciente_bucket" {
  value = module.storage.dm_paciente_bucket_name
}

output "dm_funcional_bucket" {
  value = module.storage.dm_funcional_bucket_name
}

output "dm_episodio_bucket" {
  value = module.storage.dm_episodio_bucket_name
}

output "dm_procedimientos_bucket" {
  value = module.storage.dm_procedimientos_bucket_name
}

output "dm_diagnosticos_bucket" {
  value = module.storage.dm_diagnosticos_bucket_name
}