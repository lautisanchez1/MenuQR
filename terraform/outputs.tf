output "db_instance_endpoint" {
  description = "Endpoint directo de RDS (sin proxy)"
  value       = aws_db_instance.db.address
}

output "db_proxy_endpoint" {
  description = "Endpoint de RDS Proxy"
  value       = module.rds_proxy.proxy_endpoint
}

output "db_jdbc_url" {
  description = "JDBC para Quarkus / Lambda (host = proxy)"
  value       = local.db_jdbc_url
}

output "db_name" {
  value = var.db.name
}

output "db_secret_arn" {
  description = "Secreto maestro (username/password); usar db_jdbc_url como host JDBC"
  value       = aws_db_instance.db.master_user_secret[0].secret_arn
}

output "db_client_security_group_id" {
  description = "Adjuntar a Lambda orquestador y ECS Fargate"
  value       = aws_security_group.db_client.id
}

output "backend_alb_dns_name" {
  description = "DNS del ALB (VITE_API_URL = http://<este-valor>)"
  value       = aws_lb.backend.dns_name
}

output "backend_api_url" {
  description = "URL base de la API para VITE_API_URL"
  value       = "http://${aws_lb.backend.dns_name}"
}

output "frontend_admin_s3_bucket" {
  value = module.s3-public-websites[var.admin_website_name].bucket_name
}

output "frontend_menu_s3_bucket" {
  value = module.s3-public-websites[var.user_website_name].bucket_name
}

output "frontend_admin_website_url" {
  value = module.s3-public-websites[var.admin_website_name].bucket_website_url
}

output "frontend_menu_website_url" {
  value = module.s3-public-websites[var.user_website_name].bucket_website_url
}

output "backend_ecr_repository_url" {
  description = "Push de la imagen Docker del backend"
  value       = aws_ecr_repository.backend.repository_url
}

output "backend_ecs_cluster_name" {
  value = aws_ecs_cluster.backend.name
}

output "backend_ecs_service_name" {
  value = aws_ecs_service.backend.name
}

output "backend_images_s3_bucket" {
  value = local.images_bucket_name
}

output "backend_ml_s3_bucket" {
  value = local.ml_bucket_name
}

output "jwt_public_secret_arn" {
  value = aws_secretsmanager_secret.jwt_public.arn
}

output "jwt_private_secret_arn" {
  value = aws_secretsmanager_secret.jwt_private.arn
}

output "lab_role_arn" {
  description = "Rol IAM usado por Lambda, ECS Fargate y RDS Proxy (lab)"
  value       = data.aws_iam_role.lab_role.arn
}

output "secretsmanager_vpc_endpoint_id" {
  description = "Interface endpoint; tráfico SM desde la VPC no usa NAT"
  value       = aws_vpc_endpoint.secretsmanager.id
}

output "sqs_vpc_endpoint_id" {
  description = "Interface endpoint; SendMessage del orquestador no usa NAT"
  value       = aws_vpc_endpoint.sqs.id
}

output "ecr_api_vpc_endpoint_id" {
  description = "Interface endpoint ECR API (pull de imagen Fargate)"
  value       = aws_vpc_endpoint.ecr_api.id
}

output "ecr_dkr_vpc_endpoint_id" {
  description = "Interface endpoint ECR DKR (capas Docker)"
  value       = aws_vpc_endpoint.ecr_dkr.id
}

output "ml_training_schedule_rule" {
  description = "Regla EventBridge (cron) del pipeline ML"
  value       = aws_cloudwatch_event_rule.ml_training_schedule.name
}

output "ml_training_sqs_queue_url" {
  value = aws_sqs_queue.ml-training.url
}
