module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.6.1"

  name = var.vpc.name
  cidr = var.vpc.cidr

  azs = local.azs

  public_subnets = local.public_subnet_cidrs
  private_subnets = local.private_subnet_cidrs
  database_subnets = local.db_subnet_cidrs

  enable_nat_gateway = false
}