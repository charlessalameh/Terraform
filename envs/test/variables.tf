############################################
# Variables for the test environment
############################################

# Region used by the aws provider in providers.tf
variable "aws_region" {
  description = "AWS region for this environment."
  type        = string
}

# Environment label used in names/tags (e.g., test, prod)
variable "env" {
  description = "Environment name."
  type        = string
}

# Project name for tagging and naming
variable "project" {
  description = "Project identifier for tagging/naming."
  type        = string
}

# Owner for tagging (billing/ops visibility)
variable "owner" {
  description = "Owner tag value (person or team)."
  type        = string
}

# (Optional) common tags map if you prefer to reference one value
# locals {
#   common_tags = {
#     Project     = var.project
#     Environment = var.env
#     Owner       = var.owner
#   }
# }