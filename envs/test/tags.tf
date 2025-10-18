locals {
  common_tags = {
    Project     = "devops-practice"
    Environment = var.env
    Owner       = "Charles Salameh"
    CostCenter  = "personal"
  }
}