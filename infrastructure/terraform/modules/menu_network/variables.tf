variable "vpc_cidr" {
  type        = string
  description = "CIDR de la VPC"
}

variable "name" {
  type        = string
  default     = "menu-qr-vpc"
  description = "Nombre lógico de la VPC (tags Name del submódulo)"
}
