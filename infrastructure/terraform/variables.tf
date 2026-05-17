variable "project_name" {
  type        = string
  description = "Project name prefix for resource names"
  default     = "MenuQR"
}

variable "environment" {
  type        = string
  description = "Deployment environment name"
  default     = "dev"
}

variable "vpc_cidr" {
  type        = string
  description = "VPC CIDR block"
}

variable "spa_admin_bucket_name" {
  type        = string
  description = "Globally unique S3 bucket name for the admin SPA (DNS rules apply)."
}

variable "spa_users_bucket_name" {
  type        = string
  description = "Globally unique S3 bucket name for the users SPA (DNS rules apply)."
}

variable "ml_models_bucket_name" {
  type        = string
  description = "Globally unique private S3 bucket for ML model artifacts (versioning on)."
}

variable "user_images_bucket_name" {
  type        = string
  description = "Globally unique private S3 bucket for user images (versioning on)."
}

variable "dynamodb_events_table_name" {
  type        = string
  description = "DynamoDB table name for menu analytics events (PK/SK and LSI-EventType)."
}

variable "rds_engine_version" {
  type        = string
  description = "PostgreSQL engine version for RDS"
}

variable "rds_instance_class" {
  type        = string
  description = "RDS instance class"
}

variable "rds_allocated_storage" {
  type        = number
  description = "Initial allocated storage in GB"
}

variable "rds_database_name" {
  type        = string
  description = "Initial database name"
}

variable "rds_master_username" {
  type        = string
  description = "Master username (not rdsadmin)"
}

variable "rds_backup_retention_period" {
  type        = number
  description = "Backup retention in days"
}

variable "ec2_instance_type" {
  type        = string
  description = "Instance type for the app EC2 (must match CPU arch with AMI selection logic in main.tf)."
}

variable "ec2_key_name" {
  type        = string
  nullable    = true
  description = "EC2 key pair name for SSH; set to null if not used."
}

variable "ec2_iam_instance_profile_name" {
  type        = string
  nullable    = true
  description = "IAM instance profile name for the EC2 (Learner Lab often uses LabRole as profile name). Set null to omit."
}

variable "cognito_callback_urls" {
  type        = list(string)
  description = "Allowed Cognito callback URLs"
  default     = ["http://localhost:5174/auth/callback"]
}

variable "cognito_logout_urls" {
  type        = list(string)
  description = "Allowed Cognito logout URLs"
  default     = ["http://localhost:5174/login", "http://localhost:5174/register"]
}

variable "cognito_google_client_id" {
  type        = string
  description = "Google OAuth client ID for Cognito federation"
  default     = ""
}

variable "cognito_google_client_secret" {
  type        = string
  description = "Google OAuth client secret for Cognito federation"
  default     = ""
}

variable "cognito_facebook_client_id" {
  type        = string
  description = "Facebook OAuth app ID for Cognito federation"
  default     = ""
}

variable "cognito_facebook_client_secret" {
  type        = string
  description = "Facebook OAuth app secret for Cognito federation"
  default     = ""
}
