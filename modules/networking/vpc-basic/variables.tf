variable "name" {
  type = string
  description = "Name prefix for VPC and related resources."
}

variable "cidr_block" {
  type        = string
  description = "CIDR block for the VPC (e.g., 10.10.0.0/16)."
}

variable "azs" {
  type        = list(string)
  description = "List of AZs to create public subnets in."
  validation {
    condition     = length(var.azs) >= 1
    error_message = "Provide at least one availability zone."
  }
}

variable "public_subnet_cidrs" {
  type        = list(string)
  description = "CIDRs for public subnets; must match azs length."
  validation {
    condition     = length(var.public_subnet_cidrs) == length(var.azs)
    error_message = "public_subnet_cidrs length must equal azs length."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Common tags to apply to all resources."
}