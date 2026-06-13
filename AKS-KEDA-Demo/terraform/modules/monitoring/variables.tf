variable "base_name" {
  type = string
}

variable "location" {
  type = string
}

variable "resource_group_id" {
  type = string
}

variable "user_object_id" {
  type    = string
  default = ""
}

variable "tags" {
  type    = map(string)
  default = {}
}
