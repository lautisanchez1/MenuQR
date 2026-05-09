output "bucket_id" {
  description = "Bucket ID."
  value       = aws_s3_bucket.this.id
}

output "bucket_arn" {
  description = "Bucket ARN."
  value       = aws_s3_bucket.this.arn
}

output "website_endpoint" {
  description = "HTTP endpoint for the static website (AWS region)."
  value       = aws_s3_bucket_website_configuration.this.website_endpoint
}

output "website_domain" {
  description = "Website hostname for the S3 static website endpoint."
  value       = aws_s3_bucket_website_configuration.this.website_domain
}
