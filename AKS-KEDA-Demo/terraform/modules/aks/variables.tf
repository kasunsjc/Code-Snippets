variable "cluster_name" {
  type = string
}

variable "location" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "kubernetes_version" {
  type = string
}

variable "node_count" {
  type = number
}

variable "node_vm_size" {
  type = string
}

variable "node_resource_group_name" {
  type = string
}

variable "log_analytics_workspace_id" {
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
