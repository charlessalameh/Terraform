##############################################
# BOOTSTRAP INPUTS
# Creates:
#  - S3 bucket for Terraform remote state
#  - DynamoDB table for state locking
#  - GitHub OIDC provider + IAM role scoped to your repo
##############################################

variable "region" {
  description = "AWS region for bootstrap resources."
  type        = string
  default     = "us-east-1"
}

# Must be globally unique; lowercase letters, numbers, hyphens only
variable "state_bucket_name" {
  description = "Globally unique S3 bucket name for Terraform remote state."
  type        = string
}

# Default lock table name for state locking
variable "lock_table_name" {
  description = "DynamoDB table name for Terraform state locking."
  type        = string
  default     = "terraform-locks"
}

# Your GitHub repo path (ORG_OR_USER/REPO)
variable "github_repo_path" {
  description = "GitHub repo path (ORG_OR_USER/REPO) for OIDC trust."
  type        = string
  default     = "charlessalameh/Terraform"
}