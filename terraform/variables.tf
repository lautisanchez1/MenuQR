variable "vpc" {
  type = object({
    name = string
    cidr = string
  })
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
}

variable "backend" {
  type = object({
    image_tag     = string
    desired_count = number
  })
}

variable "ml_training" {
  description = "Cron EventBridge → orquestador; SQS → worker"
  type = object({
    schedule_expression = optional(string, "cron(0 6 * * ? *)")
    schedule_enabled    = optional(bool, true)
    sqs_batch_size      = optional(number, 10)
  })
  default = {}
}