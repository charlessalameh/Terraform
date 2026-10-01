############################################
# Terraform + provider versions
############################################
terraform {
  required_version = ">= 1.10.0" # needed for S3 native state locking (use_lockfile)

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    # Phase 7: AWS DevOps Agent resources exist only in the Cloud Control provider
    awscc = {
      source  = "hashicorp/awscc"
      version = "~> 1.104"
    }
    # Phase 7: zips the trigger Lambda
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.7"
    }
  }
}
