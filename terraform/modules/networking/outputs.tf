output "vpc_id" { value = var.vpc_id }
output "public_subnet_ids" { value = var.subnet_ids }
output "private_subnet_ids" { value = var.subnet_ids }
output "sg_fhir_server_id" { value = aws_security_group.fhir_server.id }
output "sg_rds_id" { value = aws_security_group.rds.id }
output "sg_backend_services_id" { value = aws_security_group.backend_services.id }
output "sg_query_api_id" { value = aws_security_group.query_api.id }
