# terraform/modules/storage/outputs.tf

output "datalake_bucket_name" {
  value = aws_s3_bucket.datalake.bucket
}

output "datalake_bucket_arn" {
  value = aws_s3_bucket.datalake.arn
}

output "ecr_fhir_server_url" {
  value = aws_ecr_repository.fhir_server.repository_url
}

output "ecr_loader_url" {
  value = aws_ecr_repository.loader.repository_url
}