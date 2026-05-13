output "bucket_id" {
  description = "Bucket name (id)."
  value       = module.this.s3_bucket_id
}

output "bucket_arn" {
  description = "Bucket ARN."
  value       = module.this.s3_bucket_arn
}

output "website_domain" {
  description = "Static website hostname (Route53 alias / http host)."
  value       = module.this.s3_bucket_website_domain
}

output "website_endpoint" {
  description = "Regional website endpoint host (legacy S3 website format)."
  value       = module.this.s3_bucket_website_endpoint
}

output "website_url" {
  description = "HTTP URL for the SPA site root."
  value       = "http://${module.this.s3_bucket_website_domain}"
}
