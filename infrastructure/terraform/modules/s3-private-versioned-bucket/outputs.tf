output "bucket_id" {
  description = "Bucket name (id)."
  value       = module.this.s3_bucket_id
}

output "bucket_arn" {
  description = "Bucket ARN."
  value       = module.this.s3_bucket_arn
}

output "bucket_regional_domain_name" {
  description = "Regional domain name for VPC endpoint / SDK access."
  value       = module.this.s3_bucket_bucket_regional_domain_name
}
