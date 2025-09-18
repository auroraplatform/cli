# S3 bucket for ClickHouse backups
resource "aws_s3_bucket" "clickhouse_backups" {
  bucket = "clickhouse-backups-${random_id.deployment_suffix.hex}"

  tags = merge(var.tags, {
    Name = "clickhouse-backups"
    Purpose = "ClickHouse database backups"
  })
}

# S3 bucket versioning
resource "aws_s3_bucket_versioning" "clickhouse_backups_versioning" {
  bucket = aws_s3_bucket.clickhouse_backups.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket lifecycle configuration to manage old backups
resource "aws_s3_bucket_lifecycle_configuration" "clickhouse_backups_lifecycle" {
  bucket = aws_s3_bucket.clickhouse_backups.id

  rule {
    id     = "backup_retention"
    status = "Enabled"

    filter {
      prefix = ""
    }

    # Keep current version for 30 days
    noncurrent_version_expiration {
      noncurrent_days = 30
    }

    # Transition to cheaper storage after 30 days
    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    # Transition to Glacier after 90 days
    transition {
      days          = 90
      storage_class = "GLACIER"
    }
  }
}

# S3 bucket server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "clickhouse_backups_encryption" {
  bucket = aws_s3_bucket.clickhouse_backups.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3 bucket public access block
resource "aws_s3_bucket_public_access_block" "clickhouse_backups_pab" {
  bucket = aws_s3_bucket.clickhouse_backups.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# IAM policy for ClickHouse S3 backup access
resource "aws_iam_policy" "clickhouse_s3_backup_policy" {
  name        = "clickhouse-s3-backup-policy"
  description = "Allow ClickHouse instance to backup to S3"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:PutObjectAcl",
          "s3:GetObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.clickhouse_backups.arn,
          "${aws_s3_bucket.clickhouse_backups.arn}/*"
        ]
      }
    ]
  })
}

# Attach S3 backup policy to ClickHouse role
resource "aws_iam_role_policy_attachment" "clickhouse_s3_backup_attachment" {
  role       = aws_iam_role.clickhouse_role.name
  policy_arn = aws_iam_policy.clickhouse_s3_backup_policy.arn
}

# Store S3 bucket name in SSM Parameter Store
resource "aws_ssm_parameter" "clickhouse_backup_bucket" {
  name        = "/aurora/clickhouse-backup-bucket"
  description = "S3 bucket name for ClickHouse backups"
  type        = "String"
  value       = aws_s3_bucket.clickhouse_backups.bucket

  tags = merge(var.tags, {
    Name = "clickhouse-backup-bucket"
  })
}
