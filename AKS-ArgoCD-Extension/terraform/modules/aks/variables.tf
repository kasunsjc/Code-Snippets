variable "cluster_name" {
  description = "Name of the AKS cluster."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group."
  type        = string
}

variable "node_resource_group" {
  description = "Custom node resource group name."
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version."
  type        = string
}

variable "node_count" {
  description = "Default node pool node count."
  type        = number
}

variable "node_vm_size" {
  description = "Default node pool VM size."
  type        = string
}

variable "dns_zone_id" {
  description = "Resource ID of the public Azure DNS zone to attach to App Routing."
  type        = string
}

variable "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics workspace for Container Insights."
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources."
  type        = map(string)
  default     = {}
}

# --- User node pool -----------------------------------------------------------

variable "user_node_pool_name" {
  description = "Name of the user node pool."
  type        = string
  default     = "user"
}

variable "user_node_pool_vm_size" {
  description = "VM size for the user node pool."
  type        = string
  default     = "Standard_D4ds_v5"
}

variable "user_node_pool_node_count" {
  description = "Node count for the user node pool."
  type        = number
  default     = 2
}
