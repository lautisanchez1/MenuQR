# --- JWT en Secrets Manager (generado en el primer apply) ---

resource "tls_private_key" "jwt" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "aws_secretsmanager_secret" "jwt_private" {
  name_prefix = "${local.name_prefix}-jwt-private-"
}

resource "aws_secretsmanager_secret_version" "jwt_private" {
  secret_id     = aws_secretsmanager_secret.jwt_private.id
  secret_string = tls_private_key.jwt.private_key_pem
}

resource "aws_secretsmanager_secret" "jwt_public" {
  name_prefix = "${local.name_prefix}-jwt-public-"
}

resource "aws_secretsmanager_secret_version" "jwt_public" {
  secret_id     = aws_secretsmanager_secret.jwt_public.id
  secret_string = tls_private_key.jwt.public_key_pem
}

# --- ECR ---

resource "aws_ecr_repository" "backend" {
  name                 = "${local.name_prefix}-backend"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

# --- Security groups ---

resource "aws_security_group" "alb" {
  name_prefix = "${local.name_prefix}-alb-"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "fargate" {
  name_prefix = "${local.name_prefix}-fargate-"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description     = "Quarkus desde ALB"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = true
  }
}

# --- ALB ---

resource "aws_lb" "backend" {
  name               = "${local.name_prefix}-api"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = module.vpc.public_subnets
}

resource "aws_lb_target_group" "backend" {
  name_prefix = "mq-"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = module.vpc.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    path                = "/q/health/ready"
    protocol            = "HTTP"
    matcher             = "200"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 5
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_listener" "backend_http" {
  load_balancer_arn = aws_lb.backend.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend.arn
  }
}

# --- ECS ---

resource "aws_ecs_cluster" "backend" {
  name = "${local.name_prefix}-cluster"
}

resource "aws_ecs_task_definition" "backend" {
  family                   = "${local.name_prefix}-backend"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 512
  memory                   = 1024
  execution_role_arn       = local.lab_role_arn
  task_role_arn            = local.lab_role_arn

  container_definitions = jsonencode([{
    name      = "backend"
    image     = local.backend_image
    essential = true

    portMappings = [{
      containerPort = 8080
      protocol      = "tcp"
    }]

    environment = [
      { name = "DB_URL", value = local.db_jdbc_url },
      { name = "DB_SECRET_ARN", value = aws_db_instance.db.master_user_secret[0].secret_arn },
      { name = "DB_SECRET_CACHE_SECONDS", value = "300" },
      { name = "AWS_REGION", value = data.aws_region.current.region },
      { name = "S3_BUCKET", value = local.images_bucket_name },
      { name = "S3_PUBLIC_URL", value = local.s3_public_url },
      { name = "DYNAMO_TABLE", value = aws_dynamodb_table.menuqr_events.name },
      { name = "QUARKUS_PROFILE", value = "prod" },
      { name = "RECOMMENDATIONS_MODEL_S3_BUCKET", value = local.ml_bucket_name },
    ]

    secrets = [
      {
        name      = "JWT_PUBLIC_PEM"
        valueFrom = aws_secretsmanager_secret.jwt_public.arn
      },
      {
        name      = "JWT_PRIVATE_PEM"
        valueFrom = aws_secretsmanager_secret.jwt_private.arn
      }
    ]
  }])
}

resource "aws_ecs_service" "backend" {
  name            = "${local.name_prefix}-backend"
  cluster         = aws_ecs_cluster.backend.id
  task_definition = aws_ecs_task_definition.backend.arn
  desired_count   = var.backend.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = module.vpc.private_subnets
    security_groups  = [aws_security_group.fargate.id, aws_security_group.db_client.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.backend.arn
    container_name   = "backend"
    container_port   = 8080
  }

  depends_on = [aws_lb_listener.backend_http]

  lifecycle {
    ignore_changes = [desired_count]
  }
}
