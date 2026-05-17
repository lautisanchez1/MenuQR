variable "project_name" {
  type = string
}

variable "vpc_cidr" {
  type = string
}

variable "images_bucket_name" { type = string }
variable "ml_bucket_name" { type = string }
variable "user_website_name" { type = string }
variable "admin_website_name" { type = string }

variable "db" {
  type = object({
    name     = string
    username = string
  })

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]*$", var.db.name))
    error_message = "db.name debe empezar con letra y solo puede contener letras, números y guiones bajos (restricción RDS PostgreSQL; no se permiten guiones)."
  }
}

variable "backend" {
  type = object({
    image_tag     = string
    desired_count = number
  })
}

variable "ml_training" {
  type = object({
    schedule_expression = string
    schedule_enabled    = bool
    sqs_batch_size      = number
  })
}

