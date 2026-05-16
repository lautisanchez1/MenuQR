locals {
  rds_pg_major = regex("^[0-9]+", var.rds_engine_version)

  common_tags = {
    Name = module.network.vpc_name
  }

  gateway_endpoint_route_table_ids = concat(
    module.network.route_table_ids_backend,
    module.network.route_table_ids_ml,
  )

  ec2_graviton = can(regex("^[acmprst][0-9]+g\\.", var.ec2_instance_type))

  ec2_ami_ssm_parameter = local.ec2_graviton ? "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64" : "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

module "network" {
  source = "./modules/menu_network"

  vpc_cidr = var.vpc_cidr
  name     = "menu-qr-vpc"
}

# ML tier RT has no NAT route in the VPC module; add 0.0.0.0/0 → NAT (S3/DDB PL routes come from gateway endpoints).
resource "aws_route" "ml_internet_via_nat" {
  count = length(module.network.subnet_ids_ml) > 0 ? 1 : 0

  route_table_id         = module.network.route_table_ids_ml[count.index]
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = module.network.nat_gateway_id

  timeouts {
    create = "5m"
  }

  depends_on = [module.network]
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = module.network.vpc_id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = local.gateway_endpoint_route_table_ids

  tags = merge(local.common_tags, {
    Name = "${module.network.vpc_name}-s3"
    Role = "gateway-s3"
  })
}

resource "aws_vpc_endpoint" "dynamodb" {
  vpc_id            = module.network.vpc_id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.dynamodb"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = local.gateway_endpoint_route_table_ids

  tags = merge(local.common_tags, {
    Name = "${module.network.vpc_name}-dynamodb"
    Role = "gateway-dynamodb"
  })
}

module "security_group_alb" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "5.3.1"

  name        = "${module.network.vpc_name}-alb-sg"
  description = "ALB: HTTP from internet; egress HTTP to VPC/internet (no SG-to-SG egress to avoid dependency cycles)."
  vpc_id      = module.network.vpc_id

  ingress_with_cidr_blocks = [
    {
      from_port   = 80
      to_port     = 80
      protocol    = "tcp"
      description = "HTTP from internet"
      cidr_blocks = "0.0.0.0/0"
    }
  ]

  egress_with_cidr_blocks = [
    {
      rule        = "http-80-tcp"
      cidr_blocks = "0.0.0.0/0"
      description = "HTTP to targets (broader than SG-only; avoids circular refs)"
    },
  ]

  tags = merge(local.common_tags, { Name = "${module.network.vpc_name}-alb-sg" })
}

module "security_group_ec2_ml" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "5.3.1"

  name        = "${module.network.vpc_name}-ec2-ml-sg"
  description = "ML EC2: no inbound; outbound HTTP/HTTPS only."
  vpc_id      = module.network.vpc_id

  egress_with_cidr_blocks = [
    {
      rule        = "http-80-tcp"
      cidr_blocks = "0.0.0.0/0"
      description = "HTTP to internet"
    },
    {
      rule        = "https-443-tcp"
      cidr_blocks = "0.0.0.0/0"
      description = "HTTPS to internet"
    },
  ]

  tags = merge(local.common_tags, { Name = "${module.network.vpc_name}-ec2-ml-sg" })
}

module "security_group_ec2" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "5.3.1"

  name        = "${module.network.vpc_name}-ec2-sg"
  description = "App EC2: HTTP from ALB; egress PostgreSQL to VPC CIDR (RDS locked down by rds-sg ingress from this SG only)."
  vpc_id      = module.network.vpc_id

  ingress_with_source_security_group_id = [
    {
      rule                     = "http-80-tcp"
      description              = "HTTP from ALB"
      source_security_group_id = module.security_group_alb.security_group_id
    }
  ]

  egress_with_cidr_blocks = [
    {
      rule        = "postgresql-tcp"
      cidr_blocks = var.vpc_cidr
      description = "PostgreSQL within VPC"
    },
    {
      rule        = "http-80-tcp"
      cidr_blocks = "0.0.0.0/0"
      description = "HTTP to internet"
    },
    {
      rule        = "https-443-tcp"
      cidr_blocks = "0.0.0.0/0"
      description = "HTTPS to internet"
    },
  ]

  tags = merge(local.common_tags, { Name = "${module.network.vpc_name}-ec2-sg" })
}

module "security_group_rds" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "5.3.1"

  name        = "${module.network.vpc_name}-rds-sg"
  description = "PostgreSQL from application EC2 SG only; no outbound rules."
  vpc_id      = module.network.vpc_id

  ingress_with_source_security_group_id = [
    {
      rule                     = "postgresql-tcp"
      description              = "PostgreSQL from application EC2"
      source_security_group_id = module.security_group_ec2.security_group_id
    }
  ]

  tags = merge(local.common_tags, { Name = "${module.network.vpc_name}-rds-sg" })
}

# ──────────────────────────────────────────────
# ALB + Target Group + Listener
# ──────────────────────────────────────────────
resource "aws_lb" "app" {
  name               = "${module.network.vpc_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [module.security_group_alb.security_group_id]
  subnets            = module.network.subnet_ids_public

  tags = merge(local.common_tags, {
    Name = "${module.network.vpc_name}-alb"
    Role = "alb"
  })
}

resource "aws_lb_target_group" "app" {
  name     = "${module.network.vpc_name}-app-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = module.network.vpc_id

  health_check {
    path                = "/health"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = merge(local.common_tags, {
    Name = "${module.network.vpc_name}-app-tg"
    Role = "target-group"
  })
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }

  tags = merge(local.common_tags, {
    Name = "${module.network.vpc_name}-http-listener"
  })
}

module "rds" {
  source  = "terraform-aws-modules/rds/aws"
  version = "6.10.0"

  identifier = "${module.network.vpc_name}-postgres"

  engine               = "postgres"
  engine_version       = var.rds_engine_version
  family               = "postgres${local.rds_pg_major}"
  major_engine_version = local.rds_pg_major
  instance_class       = var.rds_instance_class

  allocated_storage     = var.rds_allocated_storage
  max_allocated_storage = 0

  storage_encrypted = true

  db_name  = var.rds_database_name
  username = var.rds_master_username
  port     = "5432"

  multi_az               = true
  create_db_subnet_group = true
  subnet_ids             = module.network.subnet_ids_db
  vpc_security_group_ids = [module.security_group_rds.security_group_id]

  manage_master_user_password = true

  backup_retention_period = var.rds_backup_retention_period
  skip_final_snapshot     = true
  deletion_protection     = false

  publicly_accessible = false

  tags = {
    Name = "${module.network.vpc_name}-postgres"
  }
}

module "spa_bucket_admin" {
  source = "./modules/s3-spa-bucket"

  bucket_name = var.spa_admin_bucket_name

  tags = merge(local.common_tags, {
    Role = "admin-spa"
  })
}

module "spa_bucket_users" {
  source = "./modules/s3-spa-bucket"

  bucket_name = var.spa_users_bucket_name

  tags = merge(local.common_tags, {
    Role = "users-spa"
  })
}

module "s3_private_buckets" {
  source   = "./modules/s3-private-versioned-bucket"
  for_each = {
    ml-models   = var.ml_models_bucket_name
    user-images = var.user_images_bucket_name
  }

  bucket_name = each.value

  tags = merge(local.common_tags, {
    Role = each.key
  })
}


resource "aws_dynamodb_table" "menuqr_events" {
  name         = var.dynamodb_events_table_name
  billing_mode = "PAY_PER_REQUEST"

  hash_key  = "PK"
  range_key = "SK"

  attribute {
    name = "PK"
    type = "S"
  }

  attribute {
    name = "SK"
    type = "S"
  }

  attribute {
    name = "eventTypeTimestamp"
    type = "S"
  }

  local_secondary_index {
    name            = "LSI-EventType"
    range_key       = "eventTypeTimestamp"
    projection_type = "ALL"
  }

  tags = merge(local.common_tags, {
    Name = var.dynamodb_events_table_name
    Role = "menuqr-events"
  })
}

# ──────────────────────────────────────────────
# Launch Template + Auto Scaling Group
# ──────────────────────────────────────────────
data "aws_ssm_parameter" "app_ami" {
  name = local.ec2_ami_ssm_parameter
}

resource "aws_launch_template" "app" {
  name_prefix   = "${module.network.vpc_name}-app-"
  image_id      = data.aws_ssm_parameter.app_ami.value
  instance_type = var.ec2_instance_type
  key_name      = var.ec2_key_name

  vpc_security_group_ids = [module.security_group_ec2.security_group_id]

  iam_instance_profile {
    name = var.ec2_iam_instance_profile_name
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_type           = "gp3"
      volume_size           = 30
      encrypted             = true
      delete_on_termination = true
    }
  }

  tag_specifications {
    resource_type = "instance"

    tags = merge(local.common_tags, {
      Name = "${module.network.vpc_name}-app-ec2"
      Role = "app-ec2"
    })
  }

  # Meta-argumento: crea el nuevo template antes de destruir el anterior
  lifecycle {
    create_before_destroy = true
  }

  tags = merge(local.common_tags, {
    Name = "${module.network.vpc_name}-app-lt"
    Role = "launch-template"
  })
}

resource "aws_autoscaling_group" "app" {
  name_prefix         = "${module.network.vpc_name}-app-"
  min_size            = var.asg_min_size
  desired_capacity    = var.asg_desired_capacity
  max_size            = var.asg_max_size
  vpc_zone_identifier = module.network.subnet_ids_backend
  target_group_arns   = [aws_lb_target_group.app.arn]

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  health_check_type         = "ELB"
  health_check_grace_period = 120

  tag {
    key                 = "Name"
    value               = "${module.network.vpc_name}-app-ec2"
    propagate_at_launch = true
  }

  # Meta-argumento: espera a que el ALB listener esté listo
  depends_on = [aws_lb_listener.http]
}
