variable "project_name" {
    type        = string
    description = "MenuQR"
}

variable "environment" {
    type        = string
    description = "dev, prod"
}

variable "callback_urls" {
    type        = list(string)
    description = "Allowed callback URLs for Oauth flows"
    default     = []
}

variable "logout_urls" {
    type        = list(string)
    description = "Allowed logout URLs"
    default     = []
}

variable "enable_hosted_ui" {
  type        = bool
  description = "Whether to create a Cognito-hosted UI domain"
  default     = false
}

variable "domain_prefix" {
  type        = string
  description = "Cognito hosted UI domain prefix"
}

variable "custom_attributes" {
  type = list(object({
    name       = string
    type       = string
    mutable    = bool
    min_length = optional(number)
    max_length = optional(number)
  }))
  description = "Custom user attributes to add to the pool"
  default     = []
}

variable "identity_providers" {
  type = map(object({
    provider_name     = string
    provider_type     = string
    client_id         = string
    client_secret     = string
    authorize_scopes  = list(string)
    attribute_mapping = map(string)
  }))
  description = "Federated identity providers (e.g. Google, Facebook) keyed by short name"
  default     = {}
  sensitive   = true
}

variable "tags" {
  type    = map(string)
  default = {}
}