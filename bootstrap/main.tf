##############################################
# BOOTSTRAP STACK
# Provisions:
# - S3 (versioned, encrypted, private) for Terraform state
# - DynamoDB table for state lock
# - GitHub OIDC provider + IAM role scoped to your repo
##############################################

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }
}

# Provider region
provider "aws" {
  region = var.region
}

# -----------------------------
# S3 bucket for Terraform remote state
# -----------------------------
resource "aws_s3_bucket" "tf_state" {
  bucket = var.state_bucket_name
}

resource "aws_s3_bucket_versioning" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tf_state" {
  bucket                  = aws_s3_bucket.tf_state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# -----------------------------
# DynamoDB lock table
# -----------------------------
resource "aws_dynamodb_table" "tf_lock" {
  name         = var.lock_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}

# -----------------------------
# GitHub OIDC provider (for Actions)
# -----------------------------
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]

  # Canonical GitHub Actions CA thumbprint
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1"
  ]
}

# -----------------------------
# Trust policy limited to your repo
# -----------------------------
data "aws_iam_policy_document" "gha_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    # aud must be sts.amazonaws.com
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Restrict to your repo
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repo_path}:*"]
    }
  }
}

# -----------------------------
# Role and permissions for GitHub Actions Terraform runs
# -----------------------------
resource "aws_iam_role" "gha_terraform" {
  name               = "gha-terraform"
  assume_role_policy = data.aws_iam_policy_document.gha_trust.json
}

resource "aws_iam_role_policy" "gha_permissions" {
  name = "gha-terraform-permissions"
  role = aws_iam_role.gha_terraform.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      { Effect = "Allow", Action = "ec2:*", Resource = "*" },
      { Effect = "Allow", Action = "iam:PassRole", Resource = "*" },
      { Effect = "Allow", Action = "s3:*", Resource = "*" },
      { Effect = "Allow", Action = "dynamodb:*", Resource = "*" },
      { Effect = "Allow", Action = "logs:*", Resource = "*" },
      { Effect = "Allow", Action = "cloudwatch:*", Resource = "*" },
      { Effect = "Allow", Action = "kms:*", Resource = "*" },
      { Effect = "Allow", Action = "elasticloadbalancing:*", Resource = "*" }
    ]
  })
}

# -----------------------------
# Outputs for wiring backend + GitHub secrets
# -----------------------------
output "state_bucket" {
  description = "S3 bucket for Terraform remote state."
  value       = aws_s3_bucket.tf_state.bucket
}

output "lock_table" {
  description = "DynamoDB table for Terraform state locking."
  value       = aws_dynamodb_table.tf_lock.name
}

output "gha_role_arn" {
  description = "IAM Role ARN for GitHub Actions via OIDC."
  value       = aws_iam_role.gha_terraform.arn
}