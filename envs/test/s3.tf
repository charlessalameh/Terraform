############################################
# App S3 bucket (private, versioned)
############################################

module "bucket" {
  source = "../../modules/storage/s3-bucket"
  name   = "lab-bucket-${var.project}-${var.env}"

  tags = {
    Project     = var.project
    Environment = var.env
    Owner       = var.owner
  }
}