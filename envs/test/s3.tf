resource "random_id" "suffix" { byte_length = 3 }

module "bucket" {
  source            = "../../modules/storage/s3-bucket"
  name              = "lab-bucket-${var.env}-${random_id.suffix.hex}"
  enable_versioning = true
  enable_lifecycle  = true
  tags              = local.common_tags
}

output "s3_bucket_name" { value = module.bucket.bucket_name }