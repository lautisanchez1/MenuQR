data "aws_availability_zones" "available" {
  state = "available"
}

# Rol único del lab (no se pueden crear roles IAM propios).
data "aws_iam_role" "lab_role" {
  name = "LabRole"
}

data "aws_region" "current" {}

data "aws_caller_identity" "current" {}