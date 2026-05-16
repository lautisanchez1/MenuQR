vpc = {
  cidr = "172.30.0.0/16"
  name = "MenuQR-vpc"
}

images_bucket_name = "menuQR-images"
ml_bucket_name = "menuQR-ml"
user_website_name = "menuQR-User"
admin_website_name = "menuQR-Admin"

db = {
  name     = "menudigital"
  username = "menuqr_admin"
}

backend = {
  image_tag = "latest"
  desired_count = 2
}

ml_training = {
  schedule_expression = "cron(0 6 * * ? *)"
  schedule_enabled = true
  sqs_batch_size = 10
}