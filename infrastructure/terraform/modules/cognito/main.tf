data "aws_region" "current" {}

resource "aws_cognito_user_pool" "this" {
    name = "${var.project_name}-${var.environment}-users"

    username_attributes      = ["email"]
    auto_verified_attributes = ["email"]

    password_policy {
        minimum_length    = 12
        require_lowercase = true
        require_uppercase = true
        require_numbers   = true
        require_symbols   = true
    }

    mfa_configuration = "OFF"

    # Social-only: disable Cognito-native self-signup. Federated users
    # (Google/Facebook) are still auto-created by the federation flow.
    admin_create_user_config {
        allow_admin_create_user_only = true
    }

    dynamic "schema" {
        for_each = var.custom_attributes
        content {
            name                = schema.value.name
            attribute_data_type = schema.value.type
            mutable             = schema.value.mutable

            dynamic "string_attribute_constraints" {
                for_each = schema.value.type == "String" ? [1] : []
                content {
                    min_length = try(schema.value.min_length, 1)
                    max_length = try(schema.value.max_length, 256)
                }
            }
        }
    }

    tags = var.tags
}

resource "aws_cognito_identity_provider" "external" {
  for_each = var.identity_providers

  user_pool_id  = aws_cognito_user_pool.this.id
  provider_name = each.value.provider_name
  provider_type = each.value.provider_type

  provider_details = {
    client_id        = each.value.client_id
    client_secret    = each.value.client_secret
    authorize_scopes = join(" ", each.value.authorize_scopes)
  }

  attribute_mapping = each.value.attribute_mapping
}

resource "aws_cognito_user_pool_domain" "this" {
  count = var.enable_hosted_ui ? 1 : 0

  domain       = var.domain_prefix
  user_pool_id = aws_cognito_user_pool.this.id
}

resource "aws_cognito_user_pool_client" "spa" {
  name         = "${var.project_name}-${var.environment}-spa"
  user_pool_id = aws_cognito_user_pool.this.id

  generate_secret = false

  supported_identity_providers = concat(
    ["COGNITO"],
    [for provider in aws_cognito_identity_provider.external : provider.provider_name]
  )

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["openid", "email", "profile"]
  callback_urls                       = var.callback_urls
  logout_urls                          = var.logout_urls

  access_token_validity  = 60
  id_token_validity      = 60
  refresh_token_validity = 30
  token_validity_units {
    access_token  = "minutes"
    id_token      = "minutes"
    refresh_token = "days"
  }

  prevent_user_existence_errors = "ENABLED"
}

