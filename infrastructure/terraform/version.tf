terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.62, < 6"
    }
    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.4.0"
    }
  }

  required_version = ">= 1.6.0"
}