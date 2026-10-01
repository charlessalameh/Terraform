############################################
# Network — reuses the existing vpc-basic module
# Public subnets only, NO NAT gateway (saves ~$32/month).
# Fine for a lab: nodes get public IPs, security groups still apply.
############################################
data "aws_availability_zones" "available" {
  state = "available"
}

module "vpc" {
  source              = "../modules/networking/vpc-basic"
  name                = var.project
  cidr_block          = var.vpc_cidr
  azs                 = slice(data.aws_availability_zones.available.names, 0, 2)
  public_subnet_cidrs = var.public_subnet_cidrs

  tags = {
    # lets the AWS load balancer controller / in-tree LB place internet-facing LBs here
    "kubernetes.io/role/elb" = "1"
  }
}
