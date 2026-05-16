locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 2)

  cidrs = cidrsubnets(var.vpc.cidr,
    8,8, #Public
    8,8, #Private
    8,8  #DB
  )
  public_subnet_cidrs = slice(local.cidrs, 0, 2)
  private_subnet_cidrs  = slice(local.cidrs, 2, 4)
  db_subnet_cidrs = slice(local.cidrs, 4, 6)
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.6.1"

  name = var.vpc.name
  cidr = var.vpc.cidr

  azs = local.azs

  public_subnets = local.public_subnet_cidrs
  private_subnets = local.private_subnet_cidrs
  database_subnets = local.db_subnet_cidrs


  enable_nat_gateway = true
  one_nat_gateway_per_az = true
}