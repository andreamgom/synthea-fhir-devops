# terraform/modules/compute/outputs.tf

output "ecs_cluster_name" {
  value = aws_ecs_cluster.main.name
}

output "ecs_cluster_arn" {
  value = aws_ecs_cluster.main.arn
}

output "fhir_task_definition_arn" {
  value = aws_ecs_task_definition.fhir_server.arn
}