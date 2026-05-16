locals {
  ml_training_root = "${path.module}/../ml-training"
}

module "ml_orchestrator_lambda" {
  source = "./modules/python-lambda"

  function_name = "menuqr-ml-orchestrator"
  handler       = "orchestrator_lambda.handler"
  source_dir    = "${local.ml_training_root}/lambda_dist/orchestrator"
  iam_role_arn  = data.aws_iam_role.lab_role.arn
  timeout       = 60

  vpc_subnet_ids         = module.vpc.private_subnets
  vpc_security_group_ids = [aws_security_group.db_client.id]

  environment_variables = {
    TRAINING_JOB_QUEUE_URL = aws_sqs_queue.ml-training.url
    AWS_REGION             = data.aws_region.current.region
    DB_SECRET_ARN          = aws_db_instance.db.master_user_secret[0].secret_arn
    DB_URL                 = local.db_jdbc_url
  }
}

module "ml_worker_lambda" {
  source = "./modules/python-lambda"

  function_name = "menuqr-ml-worker"
  handler       = "worker_lambda.handler"
  source_dir    = "${local.ml_training_root}/lambda_dist/worker"
  iam_role_arn  = data.aws_iam_role.lab_role.arn
  timeout       = 300

  environment_variables = {
    EVENTS_TABLE                    = aws_dynamodb_table.menuqr_events.name
    RECOMMENDATIONS_MODEL_S3_BUCKET = var.ml_bucket_name
    AWS_REGION                      = data.aws_region.current.region
  }
}

resource "aws_sqs_queue" "ml-training" {
  name = "ml-training-queue"

  visibility_timeout_seconds = 360
  message_retention_seconds  = 86400
}
