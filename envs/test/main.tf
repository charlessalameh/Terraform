############################################
# TEST ENV MAIN CONFIGURATION
# Creates: VPC, EC2 (nginx), EBS volume, S3 app bucket
############################################

# AWS provider
provider "aws" {
  region = var.aws_region
}

# VPC
module "vpc" {
  source              = "../../modules/networking/vpc-basic"
  name                = "demo-${var.env}"
  cidr_block          = "10.10.0.0/16"
  azs                 = ["us-east-1a", "us-east-1b"]
  public_subnet_cidrs = ["10.10.10.0/24", "10.10.20.0/24"]

  tags = {
    Project     = var.project
    Environment = var.env
    Owner       = var.owner
  }
}

# EC2 instance (nginx demo)
module "web" {
  source         = "../../modules/compute/ec2-instance"
  name           = "web-${var.env}"
  vpc_id         = module.vpc.vpc_id
  subnet_id      = module.vpc.public_subnet_ids[0]
  instance_type  = "t3.micro"
  user_data      = <<-EOF
                        #!/bin/bash
                        yum install -y nginx
                        systemctl enable nginx
                        echo "<h1>Hello from ${var.env}!</h1>" > /usr/share/nginx/html/index.html
                        systemctl start nginx
                        EOF
  allow_ssh_cidr = "0.0.0.0/0"
  tags = {
    Project     = var.project
    Environment = var.env
    Owner       = var.owner
  }
}

# EBS volume attached to EC2
module "web_data_disk" {
  source            = "../../modules/storage/ebs-volume"
  name              = "web-data-${var.env}"
  availability_zone = "us-east-1a"
  size_gb           = 10
  instance_id       = module.web.this_instance_id
  device_name       = "/dev/xvdf"
  tags = {
    Project     = var.project
    Environment = var.env
    Owner       = var.owner
  }
}

# S3 bucket for app files
module "bucket" {
  source = "../../modules/storage/s3-bucket"
  name   = "lab-bucket-${var.project}-${var.env}"
  tags = {
    Project     = var.project
    Environment = var.env
    Owner       = var.owner
  }
}