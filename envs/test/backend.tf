terraform {
  backend "s3" {
    bucket         = "tfstate-charles-demo" # your S3 bucket created by bootstrap
    key            = "envs/test/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-locks" # enables state locking
    encrypt        = true
  }
}