terraform {
  backend "s3" {
    bucket       = "tfstate-charles-demo"
    key          = "envs/test/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    # profile    = "bootstrap"   # optional local convenience; don’t commit if you don’t want
  }
}