output "user_pool_id" {
  value       = aws_cognito_user_pool.this.id
  description = "Cognito user pool ID"
}

output "user_pool_arn" {
  value       = aws_cognito_user_pool.this.arn
  description = "Cognito user pool ARN"
}

output "user_pool_client_id" {
  value       = aws_cognito_user_pool_client.spa.id
  description = "Cognito app client ID"
}

output "hosted_ui_domain" {
  value       = try(aws_cognito_user_pool_domain.this[0].domain, null)
  description = "Cognito hosted UI domain prefix"
}

output "hosted_ui_base_url" {
  value       = try("https://${aws_cognito_user_pool_domain.this[0].domain}.auth.${data.aws_region.current.name}.amazoncognito.com", null)
  description = "Base URL for the Cognito hosted UI"
}

output "issuer_url" {
  value       = "https://cognito-idp.${data.aws_region.current.name}.amazonaws.com/${aws_cognito_user_pool.this.id}"
  description = "OIDC issuer URL for the user pool"
}