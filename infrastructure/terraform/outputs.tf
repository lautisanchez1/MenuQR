output "rds_endpoint" {
  description = "RDS instance hostname:port"
  value       = module.rds.db_instance_endpoint
}

output "rds_address" {
  description = "RDS instance hostname"
  value       = module.rds.db_instance_address
}

output "rds_port" {
  description = "RDS port"
  value       = module.rds.db_instance_port
}

output "rds_master_user_secret_arn" {
  description = "Secrets Manager ARN for the master password (when manage_master_user_password is true)"
  value       = module.rds.db_instance_master_user_secret_arn
}

output "rds_subnet_group_id" {
  description = "DB subnet group ID"
  value       = module.rds.db_subnet_group_id
}

output "security_group_alb_id" {
  description = "Security group for ALB (alb-sg)"
  value       = module.security_group_alb.security_group_id
}

output "security_group_ec2_id" {
  description = "Security group for application EC2 (ec2-sg)"
  value       = module.security_group_ec2.security_group_id
}

output "security_group_rds_id" {
  description = "Security group for RDS (rds-sg)"
  value       = module.security_group_rds.security_group_id
}

output "security_group_ec2_ml_id" {
  description = "Security group for ML EC2 (ec2-ml-sg)"
  value       = module.security_group_ec2_ml.security_group_id
}

output "spa_admin_bucket_id" {
  description = "S3 bucket name (admin SPA static site)"
  value       = module.spa_bucket_admin.bucket_id
}

output "spa_admin_website_url" {
  description = "HTTP website URL for admin SPA bucket"
  value       = module.spa_bucket_admin.website_url
}

output "spa_users_bucket_id" {
  description = "S3 bucket name (users SPA static site)"
  value       = module.spa_bucket_users.bucket_id
}

output "spa_users_website_url" {
  description = "HTTP website URL for users SPA bucket"
  value       = module.spa_bucket_users.website_url
}

output "ml_models_bucket_id" {
  description = "Private versioned S3 bucket (ML models)"
  value       = module.s3_ml_models.bucket_id
}

output "ml_models_bucket_arn" {
  description = "ARN of the ML models bucket"
  value       = module.s3_ml_models.bucket_arn
}

output "user_images_bucket_id" {
  description = "Private versioned S3 bucket (user images)"
  value       = module.s3_user_images.bucket_id
}

output "user_images_bucket_arn" {
  description = "ARN of the user images bucket"
  value       = module.s3_user_images.bucket_arn
}

output "dynamodb_events_table_name" {
  description = "DynamoDB events table name"
  value       = aws_dynamodb_table.menuqr_events.name
}

output "dynamodb_events_table_arn" {
  description = "DynamoDB events table ARN"
  value       = aws_dynamodb_table.menuqr_events.arn
}

output "vpc_endpoint_s3_id" {
  description = "Gateway VPC endpoint ID for Amazon S3"
  value       = aws_vpc_endpoint.s3.id
}

output "vpc_endpoint_dynamodb_id" {
  description = "Gateway VPC endpoint ID for DynamoDB"
  value       = aws_vpc_endpoint.dynamodb.id
}

output "ec2_app_instance_id" {
  description = "Application EC2 instance ID (private subnet 172.30.7.0/24 with default vpc_cidr layout)"
  value       = module.ec2_app.id
}

output "ec2_app_private_ip" {
  description = "Private IP of the application EC2"
  value       = module.ec2_app.private_ip
}

output "cognito_user_pool_id" {
  description = "Cognito user pool ID"
  value       = module.cognito.user_pool_id
}

output "cognito_user_pool_client_id" {
  description = "Cognito user pool app client ID"
  value       = module.cognito.user_pool_client_id
}

output "cognito_hosted_ui_base_url" {
  description = "Cognito hosted UI base URL"
  value       = module.cognito.hosted_ui_base_url
}

output "cognito_issuer_url" {
  description = "Cognito issuer URL"
  value       = module.cognito.issuer_url
}
