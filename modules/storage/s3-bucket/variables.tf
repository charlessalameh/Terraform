variable "name" { type = string }

variable "enable_versioning" {
  type    = bool
  default = true
}

variable "enable_lifecycle" {
  type    = bool
  default = true
}

variable "tags" {
  type    = map(string)
  default = {}
}