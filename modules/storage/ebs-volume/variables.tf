variable "name" { type = string }
variable "availability_zone" { type = string }

variable "size_gb" {
  type    = number
  default = 10
}

variable "type" {
  type    = string
  default = "gp3"
}

variable "throughput" {
  type    = number
  default = 125
}

variable "iops" {
  type    = number
  default = 3000
}

variable "encrypted" {
  type    = bool
  default = true
}

variable "kms_key_id" {
  type    = string
  default = null
}

variable "instance_id" { type = string }

variable "device_name" {
  type    = string
  default = "/dev/xvdf"
}

variable "tags" {
  type    = map(string)
  default = {}
}