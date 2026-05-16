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
  description = "DynamoDB table name for menu analytics events (PK/SK only)."
}

variable "enable_recommendations_fanout" {
  type        = bool
  default     = false
  description = "Lambda orquestador -> SQS -> workers para entrenar JSON de recomendaciones por tenant. Requiere ml-training/lambda_dist/* (ver scripts/build_lambda_dists.sh)."
}

variable "recommendations_fanout_schedule_expression" {
  type        = string
  default     = "cron(15 4 * * ? *)"
  description = "Expresión EventBridge (UTC) que invoca la Lambda orquestadora."
}

variable "recommendations_model_s3_key_pattern" {
  type        = string
  default     = "recommendations/{tenantId}/model.json"
  description = "Patrón de clave S3 con {tenantId} para artefactos de recomendación (worker Lambda)."
}

variable "recommendations_fanout_worker_reserved_concurrency" {
  type        = number
  default     = null
  nullable    = true
  description = "Límite de concurrencia reservada del worker Lambda (null = sin reserva explícita)."
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
