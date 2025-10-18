


data "aws_availability_zones" "available" {
  state = "available"

  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required", "opted-in"]
  }
}

module "vpc" {
  source              = "../../modules/networking/vpc-basic"
  name                = "demo-${var.env}"
  cidr_block          = "10.10.0.0/16"
  azs                 = slice(data.aws_availability_zones.available.names, 0, 2)
  public_subnet_cidrs = ["10.10.10.0/24", "10.10.20.0/24"]
  tags                = local.common_tags
}
