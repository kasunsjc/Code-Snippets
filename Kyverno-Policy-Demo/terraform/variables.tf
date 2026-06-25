variable "resource_group_name" {
  description = "Resource group name for the demo deployment."
  type        = string
  default     = "rg-kyverno-demo"
}

variable "location" {
  description = "Azure region for all resources."
  type        = string
  default     = "northeurope"
}

variable "cluster_name" {
  description = "AKS cluster name."
  type        = string
  default     = "aks-kyverno-demo"
}

variable "kubernetes_version" {
  description = "AKS Kubernetes version."
  type        = string
  default     = "1.32"
}

variable "node_count" {
  description = "System node pool node count (used when autoscaling is disabled)."
  type        = number
  default     = 2
}

variable "node_vm_size" {
  description = "AKS node VM size."
  type        = string
  default     = "Standard_D2s_v4"
}

variable "enable_node_autoscaling" {
  description = "Enable AKS cluster autoscaler for the system node pool."
  type        = bool
  default     = true
}

variable "node_min_count" {
  description = "Minimum node count when autoscaling is enabled."
  type        = number
  default     = 2
}

variable "node_max_count" {
  description = "Maximum node count when autoscaling is enabled."
  type        = number
  default     = 4
}

variable "user_object_id" {
  description = "Optional Entra ID object ID for AKS RBAC Cluster Admin role assignment."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default = {
    environment = "demo"
    project     = "kyverno-policy-demo"
    managed-by  = "terraform"
  }
}
