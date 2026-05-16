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
    name                = string
    username            = string
  })
}