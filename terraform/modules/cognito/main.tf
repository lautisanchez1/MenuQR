data "aws_region" "current" {}
# unique suffix to avoid frequent collides on shared accounts (AWS Academy).
resource "random_id" "domain_suffix" {
  byte_length = 3
}

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

    admin_create_user_config {
        allow_admin_create_user_only = false
    }

    account_recovery_setting {
        recovery_mechanism {
            name     = "verified_email"
            priority = 1
        }
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
  for_each = nonsensitive(toset(keys(var.identity_providers)))

  user_pool_id  = aws_cognito_user_pool.this.id
  provider_name = var.identity_providers[each.key].provider_name
  provider_type = var.identity_providers[each.key].provider_type

  provider_details = {
    client_id        = var.identity_providers[each.key].client_id
    client_secret    = var.identity_providers[each.key].client_secret
    authorize_scopes = join(" ", var.identity_providers[each.key].authorize_scopes)
  }

  attribute_mapping = var.identity_providers[each.key].attribute_mapping
}

resource "aws_cognito_user_pool_domain" "this" {
  count = var.enable_hosted_ui ? 1 : 0

  domain       = "${var.domain_prefix}-${random_id.domain_suffix.hex}"
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
  callback_urls                        = var.callback_urls
  logout_urls                          = var.logout_urls

  explicit_auth_flows = [
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
  ]

  access_token_validity  = 60
  id_token_validity      = 60
  refresh_token_validity = 30
  token_validity_units {
    access_token  = "minutes"
    id_token      = "minutes"
    refresh_token = "days"
  }

  enable_token_revocation       = true
  prevent_user_existence_errors = "ENABLED"
}

