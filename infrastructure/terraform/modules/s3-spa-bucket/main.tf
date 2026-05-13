data "aws_iam_policy_document" "public_read" {
  statement {
    sid    = "AllowPublicReadObject"
    effect = "Allow"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions   = ["s3:GetObject"]
    resources = ["arn:aws:s3:::${var.bucket_name}/*"]
  }
}

module "this" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "3.15.1"

  bucket = var.bucket_name
  tags   = var.tags

  attach_policy        = true
  policy               = data.aws_iam_policy_document.public_read.json
  attach_public_policy = true

  block_public_acls       = true
  block_public_policy     = false
  ignore_public_acls      = true
  restrict_public_buckets = false

  control_object_ownership = true
  object_ownership         = "BucketOwnerEnforced"

  website = {
    index_document = "index.html"
    error_document = "index.html"
  }

  versioning = {
    enabled = false
  }
}
