locals {
  private_bucket_names = [
    var.images_bucket_name,
    var.ml_bucket_name
  ]

  public_bucket_names = [
    var.user_website_name,
    var.admin_website_name
  ]
}

module "s3-private-buckets" {
  source = "./modules/s3-private"

  for_each = toset(local.private_bucket_names)

  name = each.value
}

module "s3-public-websites" {
  source = "./modules/s3-public-website"

  for_each = toset(local.public_bucket_names)

  name = each.value
}