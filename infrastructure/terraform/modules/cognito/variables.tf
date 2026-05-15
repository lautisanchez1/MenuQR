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

variable "groups" {
  type = list(object({
    name        = string
    description = string
    precedence  = number
  }))
  description = "User groups for RBAC T"
  default     = []
}

variable "tags" {
  type    = map(string)
  default = {}
}