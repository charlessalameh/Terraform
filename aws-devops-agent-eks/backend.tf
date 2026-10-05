############################################
# Remote state — reuses the bucket from ../bootstrap
# use_lockfile = S3-native locking (no DynamoDB table needed)
############################################
terraform {
  backend "s3" {
    bucket       = "tfstate-charles-demo"
    key          = "aws-devops-agent-eks/terraform.tfstate"
    region       = "us-east-1" # region of the state bucket, not of the lab
    encrypt      = true
    use_lockfile = true
  }
}
