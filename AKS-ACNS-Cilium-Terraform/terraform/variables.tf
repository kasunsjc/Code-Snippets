variable "resource_group_name" {
  description = "Name of the resource group."
  type        = string
  default     = "rg-acns-demo"
}

variable "location" {
  description = "Azure region for all resources."
  type        = string
  default     = "northeurope"
}

variable "cluster_name" {
  description = "Name of the AKS cluster."
  type        = string
  default     = "aks-acns-demo"
}

variable "kubernetes_version" {
  description = "Kubernetes version. Must be 1.29+ for ACNS with Cilium. Leave null for the latest recommended version."
  type        = string
  default     = null
}

variable "node_vm_size" {
  description = "VM size for the system node pool."
  type        = string
  default     = "Standard_D4s_v3"
}

variable "node_count" {
  description = "Initial number of nodes in the system node pool."
  type        = number
  default     = 2
}

variable "node_min_count" {
  description = "Minimum node count for the cluster autoscaler."
  type        = number
  default     = 2
}

variable "node_max_count" {
  description = "Maximum node count for the cluster autoscaler."
  type        = number
  default     = 5
}

variable "pod_cidr" {
  description = "Pod CIDR for the Azure CNI overlay network."
  type        = string
  default     = "192.168.0.0/16"
}

variable "user_object_id" {
  description = "Entra ID object ID of the user to grant the Grafana Admin role. Leave empty to skip."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default = {
    project     = "aks-acns-cilium-demo"
    environment = "demo"
  }
}
