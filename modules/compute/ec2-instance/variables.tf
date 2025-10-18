variable "name" { type = string }
variable "vpc_id" { type = string }
variable "subnet_id" { type = string }

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "arch" {
  type    = string
  default = "x86_64" # or "arm64"
}

variable "key_name" {
  type    = string
  default = null
}

variable "user_data" {
  type    = string
  default = null
}

variable "security_group_ids" {
  type    = list(string)
  default = []
}

variable "allow_ssh_cidr" {
  type    = string
  default = "0.0.0.0/0"
}

variable "root_volume_size" {
  type    = number
  default = 8
}

variable "root_volume_type" {
  type    = string
  default = "gp3"
}

variable "iam_instance_profile" {
  type    = string
  default = null
}

variable "tags" {
  type    = map(string)
  default = {}
}