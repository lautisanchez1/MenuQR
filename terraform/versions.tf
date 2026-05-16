terraform {
  required_version = ">= 1.8.5"

  # Configuración concreta: backend.hcl (ver scripts/terraform-init-remote.sh)
  backend "s3" {}

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.71.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = ">= 4.0"
    }
  }
}
