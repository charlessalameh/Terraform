variable "vpc_name" {
  description = "Name prefix for VPC resources."
  type        = string
  default     = "demo-test"
}

variable "vpc_cidr_block" {
  description = "VPC CIDR (RFC1918)."
  type        = string
  default     = "10.10.0.0/16"
}

variable "vpc_azs" {
  description = "AZs to use for public subnets."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "public_subnet_cidrs" {
  description = "CIDRs for public subnets (match vpc_azs length)."
  type        = list(string)
  default     = ["10.10.10.0/24", "10.10.20.0/24"]
}