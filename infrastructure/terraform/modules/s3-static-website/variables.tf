variable "bucket_name" {
  description = "Globally unique name for the S3 bucket."
  type        = string
}

variable "index_document" {
  description = "Index document for the static website (SPA entry)."
  type        = string
  default     = "index.html"
}

variable "error_document" {
  description = "Error document for client-side routing (typically the same as the index for SPAs)."
  type        = string
  default     = "index.html"
}

variable "force_destroy" {
  description = "Allow deleting the bucket even when it is not empty (useful in test environments)."
  type        = bool
  default     = false
}
