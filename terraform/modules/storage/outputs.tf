# terraform/modules/storage/outputs.tf

output "fhir_datalake_bucket_name" { value = aws_s3_bucket.fhir_datalake.bucket }
output "fhir_datalake_bucket_arn" { value = aws_s3_bucket.fhir_datalake.arn }

output "dm_paciente_bucket_name" { value = aws_s3_bucket.dm_paciente.bucket }
output "dm_funcional_bucket_name" { value = aws_s3_bucket.dm_funcional.bucket }
output "dm_episodio_bucket_name" { value = aws_s3_bucket.dm_episodio.bucket }
output "dm_procedimientos_bucket_name" { value = aws_s3_bucket.dm_procedimientos.bucket }
output "dm_diagnosticos_bucket_name" { value = aws_s3_bucket.dm_diagnosticos.bucket }

output "ecr_fhir_server_url" { value = aws_ecr_repository.fhir_server.repository_url }
output "ecr_loader_url" { value = aws_ecr_repository.loader.repository_url }
output "ecr_extractor_url" { value = aws_ecr_repository.extractor.repository_url }
output "ecr_query_api_url" { value = aws_ecr_repository.query_api.repository_url }