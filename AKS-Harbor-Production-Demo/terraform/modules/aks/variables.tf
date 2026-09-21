variable "cluster_name" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "node_resource_group_name" {
  type = string
}

variable "vnet_id" {
  type = string
}

variable "vnet_subnet_id" {
  type = string
}

variable "log_analytics_workspace_id" {
  type = string
}

variable "kubernetes_version" {
  type    = string
  default = null
}

variable "user_object_id" {
  type    = string
  default = ""
}

variable "tags" {
  type = map(string)
}
