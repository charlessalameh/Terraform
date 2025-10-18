terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws    = { source = "hashicorp/aws", version = "~> 5.60" }
    random = { source = "hashicorp/random", version = "~> 3.6" }
  }
}

# <-- THIS is where the AWS region variable is consumed
provider "aws" {
  region = var.aws_region
}

# Root variables for this env
variable "aws_region" {
  type    = string
  default = "us-east-1" # <— region variable
}
variable "env" {
  type    = string
  default = "test"
}