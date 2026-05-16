# -----------------------------------------------------------------------------
# Entrenamiento de recomendaciones: orquestador Lambda -> SQS -> workers Lambda
#
# Antes de terraform apply con enable_recommendations_fanout = true:
#   bash ml-training/scripts/build_lambda_dists.sh
#   (en macOS/ARM usar imagen sam/build-python3.12, ver ml-training/README.md)
# -----------------------------------------------------------------------------

resource "aws_sqs_queue" "reco_training_dlq" {
  count = var.enable_recommendations_fanout ? 1 : 0

  name                      = "${module.network.vpc_name}-reco-train-dlq"
  message_retention_seconds = 1209600

  tags = merge(local.common_tags, { Name = "${module.network.vpc_name}-reco-train-dlq", Role = "reco-training" })
}

resource "aws_sqs_queue" "reco_training_jobs" {
  count = var.enable_recommendations_fanout ? 1 : 0

  name                       = "${module.network.vpc_name}-reco-train-jobs"
  visibility_timeout_seconds = 360
  message_retention_seconds  = 1209600
  receive_wait_time_seconds  = 0

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.reco_training_dlq[0].arn
    maxReceiveCount     = 5
  })

  tags = merge(local.common_tags, { Name = "${module.network.vpc_name}-reco-train-jobs", Role = "reco-training" })
}

resource "aws_security_group" "reco_orchestrator" {
  count = var.enable_recommendations_fanout ? 1 : 0

  name_prefix = "${module.network.vpc_name}-reco-orch-"
  vpc_id      = module.network.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "SQS, Secrets Manager, NAT"
  }

  tags = merge(local.common_tags, { Name = "${module.network.vpc_name}-reco-orch-sg", Role = "reco-training" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "rds_ingress_from_reco_orchestrator" {
  count = var.enable_recommendations_fanout ? 1 : 0

  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = module.security_group_rds.security_group_id
  source_security_group_id = aws_security_group.reco_orchestrator[0].id
  description              = "PostgreSQL desde Lambda orquestador reco"
}

data "archive_file" "reco_orchestrator_zip" {
  count       = var.enable_recommendations_fanout ? 1 : 0
  type        = "zip"
  source_dir  = "${path.module}/../../ml-training/lambda_dist/orchestrator"
  output_path = "${path.module}/.build/reco_orchestrator_lambda.zip"
}

data "archive_file" "reco_worker_zip" {
  count       = var.enable_recommendations_fanout ? 1 : 0
  type        = "zip"
  source_dir  = "${path.module}/../../ml-training/lambda_dist/worker"
  output_path = "${path.module}/.build/reco_worker_lambda.zip"
}

data "aws_iam_policy_document" "reco_orchestrator_assume" {
  count = var.enable_recommendations_fanout ? 1 : 0

  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "reco_orchestrator" {
  count              = var.enable_recommendations_fanout ? 1 : 0
  name_prefix        = "${module.network.vpc_name}-reco-orch-"
  assume_role_policy = data.aws_iam_policy_document.reco_orchestrator_assume[0].json

  tags = merge(local.common_tags, { Role = "reco-training" })
}

data "aws_iam_policy_document" "reco_orchestrator_policy" {
  count = var.enable_recommendations_fanout ? 1 : 0

  statement {
    sid       = "SqsSend"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.reco_training_jobs[0].arn]
  }

  statement {
    sid       = "SecretsRead"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [module.rds.db_instance_master_user_secret_arn]
  }

  statement {
    sid = "Logs"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"]
  }

  statement {
    sid = "VpcNetworking"
    actions = [
      "ec2:CreateNetworkInterface",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DeleteNetworkInterface",
      "ec2:AssignPrivateIpAddresses",
      "ec2:UnassignPrivateIpAddresses",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "reco_orchestrator_inline" {
  count = var.enable_recommendations_fanout ? 1 : 0

  name   = "reco-orchestrator-inline"
  role   = aws_iam_role.reco_orchestrator[0].id
  policy = data.aws_iam_policy_document.reco_orchestrator_policy[0].json
}

resource "aws_iam_role_policy_attachment" "reco_orchestrator_vpc" {
  count = var.enable_recommendations_fanout ? 1 : 0

  role       = aws_iam_role.reco_orchestrator[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_cloudwatch_log_group" "reco_orchestrator" {
  count = var.enable_recommendations_fanout ? 1 : 0

  name              = "/aws/lambda/${module.network.vpc_name}-reco-orchestrator"
  retention_in_days = 14

  tags = merge(local.common_tags, { Role = "reco-training" })
}

resource "aws_lambda_function" "reco_orchestrator" {
  count = var.enable_recommendations_fanout ? 1 : 0

  function_name = "${module.network.vpc_name}-reco-orchestrator"
  role          = aws_iam_role.reco_orchestrator[0].arn
  handler       = "orchestrator_lambda.handler"
  runtime       = "python3.12"
  timeout       = 120
  memory_size   = 256

  filename         = data.archive_file.reco_orchestrator_zip[0].output_path
  source_code_hash = data.archive_file.reco_orchestrator_zip[0].output_base64sha256

  vpc_config {
    subnet_ids         = module.network.subnet_ids_backend
    security_group_ids = [aws_security_group.reco_orchestrator[0].id]
  }

  environment {
    variables = {
      TRAINING_JOB_QUEUE_URL = aws_sqs_queue.reco_training_jobs[0].url
      DB_URL                 = "jdbc:postgresql://${module.rds.db_instance_address}:5432/${var.rds_database_name}?sslmode=require"
      DB_SECRET_ARN          = module.rds.db_instance_master_user_secret_arn
      AWS_REGION             = data.aws_region.current.name
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.reco_orchestrator_vpc,
    aws_cloudwatch_log_group.reco_orchestrator,
  ]

  tags = merge(local.common_tags, { Role = "reco-training" })
}

# --- Worker (sin VPC: DynamoDB + S3)

data "aws_iam_policy_document" "reco_worker_assume" {
  count = var.enable_recommendations_fanout ? 1 : 0

  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "reco_worker" {
  count              = var.enable_recommendations_fanout ? 1 : 0
  name_prefix        = "${module.network.vpc_name}-reco-worker-"
  assume_role_policy = data.aws_iam_policy_document.reco_worker_assume[0].json

  tags = merge(local.common_tags, { Role = "reco-training" })
}

data "aws_iam_policy_document" "reco_worker_policy" {
  count = var.enable_recommendations_fanout ? 1 : 0

  statement {
    sid       = "DynamoQuery"
    actions   = ["dynamodb:Query"]
    resources = [aws_dynamodb_table.menuqr_events.arn]
  }

  statement {
    sid       = "S3PutModels"
    actions   = ["s3:PutObject"]
    resources = ["${module.s3_ml_models.bucket_arn}/*"]
  }

  statement {
    sid = "SqsConsume"
    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
      "sqs:ChangeMessageVisibility",
    ]
    resources = [aws_sqs_queue.reco_training_jobs[0].arn]
  }

  statement {
    sid = "Logs"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"]
  }
}

resource "aws_iam_role_policy" "reco_worker_inline" {
  count = var.enable_recommendations_fanout ? 1 : 0

  name   = "reco-worker-inline"
  role   = aws_iam_role.reco_worker[0].id
  policy = data.aws_iam_policy_document.reco_worker_policy[0].json
}

resource "aws_cloudwatch_log_group" "reco_worker" {
  count = var.enable_recommendations_fanout ? 1 : 0

  name              = "/aws/lambda/${module.network.vpc_name}-reco-worker"
  retention_in_days = 14

  tags = merge(local.common_tags, { Role = "reco-training" })
}

resource "aws_lambda_function" "reco_worker" {
  count = var.enable_recommendations_fanout ? 1 : 0

  function_name = "${module.network.vpc_name}-reco-worker"
  role          = aws_iam_role.reco_worker[0].arn
  handler       = "worker_lambda.handler"
  runtime       = "python3.12"
  timeout       = 240
  memory_size   = 512

  filename         = data.archive_file.reco_worker_zip[0].output_path
  source_code_hash = data.archive_file.reco_worker_zip[0].output_base64sha256

  reserved_concurrent_executions = var.recommendations_fanout_worker_reserved_concurrency

  environment {
    variables = {
      EVENTS_TABLE                         = var.dynamodb_events_table_name
      RECOMMENDATIONS_MODEL_S3_BUCKET      = module.s3_ml_models.bucket_id
      RECOMMENDATIONS_MODEL_S3_KEY_PATTERN = var.recommendations_model_s3_key_pattern
      AWS_REGION                           = data.aws_region.current.name
    }
  }

  depends_on = [aws_cloudwatch_log_group.reco_worker]

  tags = merge(local.common_tags, { Role = "reco-training" })
}

resource "aws_lambda_event_source_mapping" "reco_worker_sqs" {
  count = var.enable_recommendations_fanout ? 1 : 0

  event_source_arn = aws_sqs_queue.reco_training_jobs[0].arn
  function_name    = aws_lambda_function.reco_worker[0].arn
  batch_size       = 5

  function_response_types = ["ReportBatchItemFailures"]
}

resource "aws_cloudwatch_event_rule" "reco_orchestrator_schedule" {
  count = var.enable_recommendations_fanout ? 1 : 0

  name_prefix         = "${module.network.vpc_name}-reco-orch-"
  schedule_expression = var.recommendations_fanout_schedule_expression
  description         = "Dispara la Lambda orquestador de entrenamiento reco"

  tags = merge(local.common_tags, { Role = "reco-training" })
}

resource "aws_cloudwatch_event_target" "reco_orchestrator" {
  count = var.enable_recommendations_fanout ? 1 : 0

  rule      = aws_cloudwatch_event_rule.reco_orchestrator_schedule[0].name
  target_id = "RecoOrchestratorLambda"
  arn       = aws_lambda_function.reco_orchestrator[0].arn
}

resource "aws_lambda_permission" "reco_orchestrator_events" {
  count = var.enable_recommendations_fanout ? 1 : 0

  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.reco_orchestrator[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.reco_orchestrator_schedule[0].arn
}
