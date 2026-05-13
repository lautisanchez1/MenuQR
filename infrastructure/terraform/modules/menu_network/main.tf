data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 2)

  public_subnets  = [for i in range(1, 3) : cidrsubnet(var.vpc_cidr, 8, i)]
  backend_subnets = [for i in range(3, 5) : cidrsubnet(var.vpc_cidr, 8, i)]
  db_subnets      = [for i in range(5, 7) : cidrsubnet(var.vpc_cidr, 8, i)]
  ml_subnets      = [cidrsubnet(var.vpc_cidr, 8, 7)]
}

# Los nombres private/database/elasticache_* son solo la API del módulo upstream;
# en outputs este módulo expone solo nombres por tier (public/backend/db/ml).
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.5.1"

  name = var.name
  cidr = var.vpc_cidr

  azs             = local.azs
  public_subnets  = local.public_subnets
  private_subnets = local.backend_subnets

  database_subnets = local.db_subnets

  elasticache_subnets = local.ml_subnets

  enable_nat_gateway = true
  single_nat_gateway = true

  public_route_table_tags = { Tier = "public" }

  private_subnet_suffix    = "backend"
  private_subnet_tags      = { Tier = "backend" }
  private_route_table_tags = { Tier = "backend" }

  create_database_subnet_route_table = true
  create_database_nat_gateway_route  = false
  database_subnet_suffix             = "db"
  database_subnet_tags               = { Tier = "db" }
  database_route_table_tags          = { Tier = "db" }
  create_database_subnet_group       = false

  create_elasticache_subnet_route_table = true
  create_elasticache_subnet_group       = false
  elasticache_subnet_suffix             = "ml"
  elasticache_subnet_tags               = { Tier = "ml" }
  elasticache_route_table_tags          = { Tier = "ml" }

  tags = {
    Name = var.name
  }
}
