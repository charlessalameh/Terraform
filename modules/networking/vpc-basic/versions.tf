# Pin Terraform + AWS provider versions for reproducibility.
terraform {
  required_version = ">= 1.6.0"
  required_providers { aws = { source = "hashicorp/aws", version = "~> 5.60" } }
}