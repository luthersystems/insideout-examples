terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.5"
    }
  }
}


# Unique suffix to keep bucket name globally unique
resource "random_id" "suffix" {
  byte_length = 3
}

# -----------------------------------------------------------------------------
# Customer managed KMS key for the bucket
# -----------------------------------------------------------------------------
# A key this stack owns, not SSE-S3 or aws/s3 (Trivy AWS-0132): its key policy
# and CloudTrail record of every decrypt are under the stack's control, it can
# be disabled to cut off all reads at once, and it rotates every year.
data "aws_caller_identity" "current" {}

# The provider's region, where the bucket is made. var.region is not used:
# a stack may set it differently from the provider, and the condition below
# must name the region S3 actually calls KMS from.
data "aws_region" "current" {}

data "aws_iam_policy_document" "bucket_key" {
  # The account administers the key through IAM, as with any default key
  # policy, so the key can never become unmanageable.
  statement {
    sid       = "AccountAdministersKey"
    effect    = "Allow"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }

  # Any principal in this account may use the key, but only through S3 in
  # this region. This is what the aws/s3 key allows, so a role that can read
  # or write the bucket today (the Bedrock knowledge base, a Lambda) keeps
  # working with no kms:Decrypt grant of its own.
  statement {
    sid    = "UseThroughS3InThisAccount"
    effect = "Allow"
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
    ]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    condition {
      test     = "StringEquals"
      variable = "kms:CallerAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["s3.${data.aws_region.current.region}.amazonaws.com"]
    }
  }
}

resource "aws_kms_key" "bucket" {
  description             = "Encrypts the ${var.project} S3 bucket"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.bucket_key.json

  tags = merge({ Name = "${var.project}-bucket" }, var.tags)
}

# -----------------------------------------------------------------------------
# S3 bucket (private, SSE-KMS with the key above, public access blocked)
# -----------------------------------------------------------------------------
resource "aws_s3_bucket" "this" {
  bucket        = lower(replace("${var.project}-${random_id.suffix.hex}", "/[^a-z0-9.-]/", "-"))
  force_destroy = var.force_destroy

  tags = merge({ Name = "${var.project}-bucket" }, var.tags)
}

# Bucket ownership/ACL model (recommended)
resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket                  = aws_s3_bucket.this.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Server-side encryption with the stack's KMS key. The S3 bucket key cuts
# the KMS calls (and their cost) to one per bucket key period instead of one
# per object.
resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.bucket.arn
    }
    bucket_key_enabled = true
  }
}

# Versioning (matches card: Versioning Yes/No)
resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id
  versioning_configuration {
    status = var.versioning ? "Enabled" : "Suspended"
  }
}

# Optional: lifecycle example for current objects (disabled by default)
resource "aws_s3_bucket_lifecycle_configuration" "this" {
  count  = var.enable_lifecycle ? 1 : 0
  bucket = aws_s3_bucket.this.id

  rule {
    id     = "standard-transitions"
    status = "Enabled"

    # REQUIRED: filter or prefix — empty prefix means "match all objects"
    filter {
      prefix = ""
    }

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    noncurrent_version_transition {
      noncurrent_days = 30
      storage_class   = "GLACIER"
    }
  }
}
