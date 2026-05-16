vpc_cidr = "172.30.0.0/16"

spa_admin_bucket_name = "menu-qr-spa-admin-424242"
spa_users_bucket_name = "menu-qr-spa-users-424242"

ml_models_bucket_name   = "menu-qr-ml-models-424242"
user_images_bucket_name = "menu-qr-user-images-424242"

dynamodb_events_table_name = "menuqr-events"

rds_engine_version          = "16"
rds_instance_class          = "db.t4g.micro"
rds_allocated_storage       = 20
rds_database_name           = "app"
rds_master_username         = "dbadmin"
rds_backup_retention_period = 7

ec2_instance_type             = "t3.micro"
ec2_key_name                  = null
ec2_iam_instance_profile_name = "LabInstanceProfile"
