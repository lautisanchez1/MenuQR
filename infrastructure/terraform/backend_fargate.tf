# -----------------------------------------------------------------------------
# Backend API en ECS Fargate + ALB (HTTP 80 → Quarkus 8080).
# Activar con enable_backend_fargate = true. JWT: Secrets Manager → env
# JWT_PUBLIC_PEM / JWT_PRIVATE_PEM (PEM en texto plano, un secreto por clave).
# La imagen usa entrypoint.sh para escribir /tmp/*.pem y fijar -Dmp.jwt...
# -----------------------------------------------------------------------------

locals {
  fargate_container_image = (
    var.enable_backend_fargate ? (
      trimspace(var.backend_container_image) != "" ? trimspace(var.backend_container_image) : (
        var.backend_create_ecr_repository ? "${aws_ecr_repository.backend[0].repository_url}:latest" : ""
      )
    ) : ""
  )

  # CMK usadas por secretos (JWT inyectados + lectura RDS en runtime); sin duplicados.
  fargate_kms_customer_key_arns = distinct([
    for a in var.backend_fargate_kms_customer_key_arns : trimspace(a)
    if trimspace(a) != ""
  ])

  # Rol de ejecución: descifrado JWT + pull de imágenes ECR cifradas con CMK propia.
  fargate_ecs_exec_kms_decrypt_arns = distinct(concat(
    local.fargate_kms_customer_key_arns,
    trimspace(var.backend_ecr_repository_kms_key_arn) != "" ? [trimspace(var.backend_ecr_repository_kms_key_arn)] : []
  ))

  ecr_repository_encryption_type = trimspace(var.backend_ecr_repository_kms_key_arn) != "" ? "KMS" : "AES256"
}

check "backend_fargate_jwt_secrets" {
  assert {
    condition     = !var.enable_backend_fargate || (length(trimspace(var.jwt_public_pem_secret_arn)) > 0 && length(trimspace(var.jwt_private_pem_secret_arn)) > 0)
    error_message = "Con enable_backend_fargate=true debes definir jwt_public_pem_secret_arn y jwt_private_pem_secret_arn (ARN de secretos con el PEM en texto)."
  }
}

check "backend_fargate_container_image" {
  assert {
    condition     = !var.enable_backend_fargate || local.fargate_container_image != ""
    error_message = "Con enable_backend_fargate=true define backend_container_image o deja backend_create_ecr_repository=true para usar el ECR creado por Terraform."
  }
}

resource "aws_ecr_repository" "backend" {
  count = var.enable_backend_fargate && var.backend_create_ecr_repository ? 1 : 0

  name                 = "${module.network.vpc_name}-backend"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = local.ecr_repository_encryption_type
    kms_key         = local.ecr_repository_encryption_type == "KMS" ? trimspace(var.backend_ecr_repository_kms_key_arn) : null
  }

  tags = merge(local.common_tags, {
    Name = "${module.network.vpc_name}-backend-ecr"
    Role = "backend-api"
  })
}

resource "aws_cloudwatch_log_group" "backend_ecs" {
  count = var.enable_backend_fargate ? 1 : 0

  name              = "/ecs/${module.network.vpc_name}-backend"
  retention_in_days = var.backend_fargate_log_retention_days

  tags = merge(local.common_tags, { Name = "${module.network.vpc_name}-backend-ecs-logs", Role = "backend-api" })
}

data "aws_iam_policy_document" "backend_ecs_exec_assume" {
  count = var.enable_backend_fargate ? 1 : 0

  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "backend_ecs_exec" {
  count = var.enable_backend_fargate ? 1 : 0

  name_prefix        = "${module.network.vpc_name}-ecs-exec-"
  assume_role_policy = data.aws_iam_policy_document.backend_ecs_exec_assume[0].json

  tags = merge(local.common_tags, { Role = "backend-ecs-exec" })
}

resource "aws_iam_role_policy_attachment" "backend_ecs_exec_managed" {
  count = var.enable_backend_fargate ? 1 : 0

  role       = aws_iam_role.backend_ecs_exec[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_iam_policy_document" "backend_ecs_exec_secrets" {
  count = var.enable_backend_fargate ? 1 : 0

  statement {
    sid       = "JwtPemFromSecretsManager"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [var.jwt_public_pem_secret_arn, var.jwt_private_pem_secret_arn]
  }

  dynamic "statement" {
    for_each = length(local.fargate_ecs_exec_kms_decrypt_arns) > 0 ? [1] : []
    content {
      sid    = "KmsDecryptForExecRole"
      effect = "Allow"
      actions = [
        "kms:Decrypt",
        "kms:DescribeKey",
      ]
      resources = local.fargate_ecs_exec_kms_decrypt_arns
    }
  }
}

resource "aws_iam_role_policy" "backend_ecs_exec_secrets" {
  count = var.enable_backend_fargate ? 1 : 0

  name   = "${module.network.vpc_name}-ecs-exec-jwt"
  role   = aws_iam_role.backend_ecs_exec[0].id
  policy = data.aws_iam_policy_document.backend_ecs_exec_secrets[0].json
}

data "aws_iam_policy_document" "backend_ecs_task_assume" {
  count = var.enable_backend_fargate ? 1 : 0

  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "backend_ecs_task" {
  count = var.enable_backend_fargate ? 1 : 0

  name_prefix        = "${module.network.vpc_name}-ecs-task-"
  assume_role_policy = data.aws_iam_policy_document.backend_ecs_task_assume[0].json

  tags = merge(local.common_tags, { Role = "backend-ecs-task" })
}

data "aws_iam_policy_document" "backend_ecs_task_policy" {
  count = var.enable_backend_fargate ? 1 : 0

  statement {
    sid    = "S3UserImages"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket",
    ]
    resources = [
      module.s3_user_images.bucket_arn,
      "${module.s3_user_images.bucket_arn}/*",
    ]
  }

  statement {
    sid    = "S3MlModels"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:ListBucket",
    ]
    resources = [
      module.s3_ml_models.bucket_arn,
      "${module.s3_ml_models.bucket_arn}/*",
    ]
  }

  statement {
    sid    = "DynamoEvents"
    effect = "Allow"
    actions = [
      "dynamodb:PutItem",
      "dynamodb:GetItem",
      "dynamodb:Query",
      "dynamodb:Scan",
      "dynamodb:UpdateItem",
      "dynamodb:DeleteItem",
      "dynamodb:BatchWriteItem",
      "dynamodb:BatchGetItem",
      "dynamodb:DescribeTable",
    ]
    resources = [aws_dynamodb_table.menuqr_events.arn]
  }

  statement {
    sid       = "RdsCredentialsSecret"
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [module.rds.db_instance_master_user_secret_arn]
  }

  dynamic "statement" {
    for_each = length(local.fargate_kms_customer_key_arns) > 0 ? [1] : []
    content {
      sid    = "KmsDecryptForTaskRole"
      effect = "Allow"
      actions = [
        "kms:Decrypt",
        "kms:DescribeKey",
      ]
      resources = local.fargate_kms_customer_key_arns
    }
  }
}

resource "aws_iam_role_policy" "backend_ecs_task" {
  count = var.enable_backend_fargate ? 1 : 0

  name   = "${module.network.vpc_name}-backend-task"
  role   = aws_iam_role.backend_ecs_task[0].id
  policy = data.aws_iam_policy_document.backend_ecs_task_policy[0].json
}

module "security_group_backend_ecs" {
  count   = var.enable_backend_fargate ? 1 : 0
  source  = "terraform-aws-modules/security-group/aws"
  version = "5.3.1"

  name        = "${module.network.vpc_name}-backend-ecs-sg"
  description = "ECS Fargate backend: 8080 desde ALB; egress Postgres + HTTP/HTTPS."
  vpc_id      = module.network.vpc_id

  ingress_with_source_security_group_id = [
    {
      from_port                = 8080
      to_port                  = 8080
      protocol                 = "tcp"
      description              = "Quarkus HTTP desde ALB"
      source_security_group_id = module.security_group_alb.security_group_id
    }
  ]

  egress_with_cidr_blocks = [
    {
      rule        = "postgresql-tcp"
      cidr_blocks = var.vpc_cidr
      description = "PostgreSQL hacia RDS en VPC"
    },
    {
      rule        = "http-80-tcp"
      cidr_blocks = "0.0.0.0/0"
      description = "HTTP (ECR, etc.)"
    },
    {
      rule        = "https-443-tcp"
      cidr_blocks = "0.0.0.0/0"
      description = "HTTPS (ECR, APIs)"
    },
  ]

  tags = merge(local.common_tags, { Name = "${module.network.vpc_name}-backend-ecs-sg", Role = "backend-api" })
}

resource "aws_security_group_rule" "rds_ingress_from_backend_ecs" {
  count = var.enable_backend_fargate ? 1 : 0

  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = module.security_group_rds.security_group_id
  source_security_group_id = module.security_group_backend_ecs[0].security_group_id
  description              = "PostgreSQL desde backend ECS Fargate"
}

resource "aws_lb" "backend" {
  count = var.enable_backend_fargate ? 1 : 0

  name               = substr(lower(replace("${module.network.vpc_name}-api", "_", "-")), 0, 32)
  load_balancer_type = "application"
  security_groups    = [module.security_group_alb.security_group_id]
  subnets            = module.network.subnet_ids_public

  tags = merge(local.common_tags, { Name = "${module.network.vpc_name}-api-alb", Role = "backend-alb" })
}

resource "aws_lb_target_group" "backend" {
  count = var.enable_backend_fargate ? 1 : 0

  name        = substr(lower(replace("${module.network.vpc_name}-tg", "_", "-")), 0, 32)
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = module.network.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    path                = "/q/health/ready"
    protocol            = "HTTP"
    matcher             = "200"
  }

  deregistration_delay = 30

  tags = merge(local.common_tags, { Name = "${module.network.vpc_name}-backend-tg", Role = "backend-api" })
}

resource "aws_lb_listener" "backend_http" {
  count = var.enable_backend_fargate ? 1 : 0

  load_balancer_arn = aws_lb.backend[0].arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend[0].arn
  }
}

resource "aws_ecs_cluster" "backend" {
  count = var.enable_backend_fargate ? 1 : 0

  name = "${module.network.vpc_name}-backend"

  setting {
    name  = "containerInsights"
    value = "disabled"
  }

  tags = merge(local.common_tags, { Name = "${module.network.vpc_name}-ecs-backend", Role = "backend-api" })
}

resource "aws_ecs_task_definition" "backend" {
  count = var.enable_backend_fargate ? 1 : 0

  family                   = "${module.network.vpc_name}-backend"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = tostring(var.backend_fargate_cpu)
  memory                   = tostring(var.backend_fargate_memory)
  execution_role_arn       = aws_iam_role.backend_ecs_exec[0].arn
  task_role_arn            = aws_iam_role.backend_ecs_task[0].arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = var.backend_fargate_cpu_architecture
  }

  container_definitions = jsonencode([{
    name      = "backend"
    image     = local.fargate_container_image
    essential = true

    portMappings = [{
      containerPort = 8080
      protocol      = "tcp"
    }]

    environment = [
      { name = "QUARKUS_PROFILE", value = "prod" },
      { name = "AWS_REGION", value = data.aws_region.current.name },
      {
        name  = "DB_URL"
        value = "jdbc:postgresql://${module.rds.db_instance_address}:${module.rds.db_instance_port}/${var.rds_database_name}"
      },
      { name = "DB_SECRET_ARN", value = module.rds.db_instance_master_user_secret_arn },
      { name = "S3_BUCKET", value = module.s3_user_images.bucket_id },
      { name = "DYNAMO_TABLE", value = aws_dynamodb_table.menuqr_events.name },
      { name = "RECOMMENDATIONS_MODEL_S3_BUCKET", value = module.s3_ml_models.bucket_id },
      { name = "RECOMMENDATIONS_MODEL_S3_KEY_PATTERN", value = var.recommendations_model_s3_key_pattern },
    ]

    secrets = [
      { name = "JWT_PUBLIC_PEM", valueFrom = var.jwt_public_pem_secret_arn },
      { name = "JWT_PRIVATE_PEM", valueFrom = var.jwt_private_pem_secret_arn },
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.backend_ecs[0].name
        "awslogs-region"        = data.aws_region.current.name
        "awslogs-stream-prefix" = "backend"
      }
    }
  }])

  tags = merge(local.common_tags, { Name = "${module.network.vpc_name}-backend-taskdef", Role = "backend-api" })
}

resource "aws_ecs_service" "backend" {
  count = var.enable_backend_fargate ? 1 : 0

  name             = "${module.network.vpc_name}-backend"
  cluster          = aws_ecs_cluster.backend[0].id
  task_definition  = aws_ecs_task_definition.backend[0].arn
  desired_count    = var.backend_fargate_desired_count
  launch_type      = "FARGATE"
  platform_version = "LATEST"

  network_configuration {
    subnets          = module.network.subnet_ids_backend
    security_groups  = [module.security_group_backend_ecs[0].security_group_id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.backend[0].arn
    container_name   = "backend"
    container_port   = 8080
  }

  depends_on = [aws_lb_listener.backend_http]

  tags = merge(local.common_tags, { Name = "${module.network.vpc_name}-backend-svc", Role = "backend-api" })
}
