terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.62, < 6"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.6"
    }
  }

  required_version = ">= 1.6.0"
}