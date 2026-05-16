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
  default     = "recommendations/{tenantId}/model.bin"
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

variable "enable_backend_ec2" {
  type        = bool
  default     = true
  description = "Si false, no se crea la instancia EC2 de la API (p. ej. migración a Fargate)."
}

variable "enable_backend_fargate" {
  type        = bool
  default     = false
  description = "Si true, despliega ECS Fargate + ALB para el backend Quarkus (imagen ECR o backend_container_image)."
}

variable "backend_create_ecr_repository" {
  type        = bool
  default     = true
  description = "Crea repositorio ECR para la imagen del backend (deshabilitar si usas imagen externa en backend_container_image)."
}

variable "backend_container_image" {
  type        = string
  default     = ""
  description = "URI completa de la imagen (ej. 123.dkr.ecr.region.amazonaws.com/repo:tag). Vacío = usar ECR creado por Terraform con tag latest."
}

variable "backend_fargate_cpu" {
  type        = number
  default     = 512
  description = "CPU units Fargate (256, 512, 1024, ...)."
}

variable "backend_fargate_memory" {
  type        = number
  default     = 1024
  description = "Memoria MB Fargate (compatible con backend_fargate_cpu; ver matriz AWS)."
}

variable "backend_fargate_desired_count" {
  type        = number
  default     = 1
  description = "Número deseado de tasks del servicio ECS."
}

variable "backend_fargate_cpu_architecture" {
  type        = string
  default     = "X86_64"
  description = "X86_64 o ARM64 (debe coincidir con el build de la imagen Docker)."
}

variable "backend_fargate_log_retention_days" {
  type        = number
  default     = 14
  description = "Retención de logs CloudWatch del contenedor backend."
}

variable "jwt_public_pem_secret_arn" {
  type        = string
  default     = ""
  description = "ARN del secreto con el PEM de la clave pública JWT (texto plano). Obligatorio si enable_backend_fargate=true."
}

variable "jwt_private_pem_secret_arn" {
  type        = string
  default     = ""
  description = "ARN del secreto con el PEM de la clave privada de firma JWT (texto plano). Obligatorio si enable_backend_fargate=true."
}

variable "backend_fargate_kms_customer_key_arns" {
  type        = list(string)
  default     = []
  description = "ARNs de CMK KMS para descifrar secretos cifrados con clave propia: se concede kms:Decrypt al rol de ejecución ECS (inyección JWT desde Secrets Manager) y al rol de task (p. ej. secreto maestro de RDS). Vacío si todos los secretos usan la clave gestionada por AWS."
}

variable "backend_ecr_repository_kms_key_arn" {
  type        = string
  default     = ""
  description = "Opcional: ARN de CMK para cifrar el repositorio ECR del backend (encryption_type KMS). El rol de ejecución ECS recibe kms:Decrypt para poder hacer pull de la imagen."
}
