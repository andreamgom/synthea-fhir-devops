# terraform/modules/database/outputs.tf

output "endpoint" {
  description = "Endpoint de conexión a RDS (host:port)"
  value       = aws_db_instance.postgres.endpoint
}

output "db_name" {
  value = aws_db_instance.postgres.db_name
}

output "db_username" {
  value = aws_db_instance.postgres.username
}