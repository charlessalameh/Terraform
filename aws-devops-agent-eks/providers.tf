############################################
# AWS provider — every resource gets the same tags,
# so Cost Explorer can show exactly what this lab costs
############################################
provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = var.project
      Owner     = var.owner
      ManagedBy = "terraform"
      Lab       = "aws-devops-agent-eks"
    }
  }
}
