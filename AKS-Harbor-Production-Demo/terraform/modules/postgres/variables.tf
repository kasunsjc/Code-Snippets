variable "project" {
  type = string
}

variable "environment" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "subnet_id" {
  type = string
}

variable "private_dns_zone_id" {
  type = string
}

variable "user_object_id" {
  type    = string
  default = ""
}

variable "tenant_id" {
  type = string
}

variable "tags" {
  type = map(string)
}
