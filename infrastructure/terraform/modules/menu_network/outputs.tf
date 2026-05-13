output "vpc_id" {
  description = "ID de la VPC"
  value       = module.vpc.vpc_id
}

output "vpc_name" {
  description = "Nombre de la VPC (tag Name)"
  value       = module.vpc.name
}

output "subnet_ids_public" {
  description = "Subredes públicas"
  value       = module.vpc.public_subnets
}

output "subnet_ids_backend" {
  description = "Subredes backend (tabla con NAT + endpoints)"
  value       = module.vpc.private_subnets
}

output "subnet_ids_db" {
  description = "Subredes base de datos (sin ruta a Internet ni endpoints)"
  value       = module.vpc.database_subnets
}

output "subnet_ids_ml" {
  description = "Subredes ML (NAT + endpoints)"
  value       = module.vpc.elasticache_subnets
}

output "route_table_ids_public" {
  value = module.vpc.public_route_table_ids
}

output "route_table_ids_backend" {
  value = module.vpc.private_route_table_ids
}

output "route_table_ids_db" {
  value = module.vpc.database_route_table_ids
}

output "route_table_ids_ml" {
  value = module.vpc.elasticache_route_table_ids
}

output "nat_gateway_id" {
  description = "NAT gateway (single_nat_gateway)"
  value       = module.vpc.natgw_ids[0]
}
