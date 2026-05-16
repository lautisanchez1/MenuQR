locals {
  route_table_ids = module.vpc.private_route_table_ids

  gateway_endpoints = [
    "com.amazonaws.${data.aws_region.current.region}.s3",
    "com.amazonaws.${data.aws_region.current.region}.dynamodb"
  ]

}

resource "aws_vpc_endpoint" "gateway_endpoints" {
  for_each = toset(local.gateway_endpoints)

  vpc_id            = module.vpc.vpc_id
  service_name      = each.value
  vpc_endpoint_type = "Gateway"
  route_table_ids   = local.route_table_ids
}

