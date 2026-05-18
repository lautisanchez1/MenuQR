module "cognito_custom_message_lambda" {
  source = "./modules/python-lambda"

  function_name = "${local.name_prefix}-cognito-custom-message"
  handler       = "custom_message.handler"
  source_dir    = "${path.module}/../cognito-custom-message"
  iam_role_arn  = data.aws_iam_role.lab_role.arn
  timeout       = 10
}

resource "aws_lambda_permission" "cognito_custom_message" {
  statement_id  = "AllowCognitoInvoke"
  action        = "lambda:InvokeFunction"
  function_name = module.cognito_custom_message_lambda.function_name
  principal     = "cognito-idp.amazonaws.com"
  source_arn    = aws_cognito_user_pool.main.arn
}
