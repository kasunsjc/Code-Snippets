variable "location" {
  description = "Azure region to deploy into."
  type        = string
  default     = "northeurope"
}

variable "resource_group_name" {
  description = "Name of the resource group."
  type        = string
  default     = "rg-aks-opa-policy-demo"
}

variable "cluster_name" {
  description = "Name of the AKS cluster."
  type        = string
  default     = "aks-opa-policy-demo"
}

variable "kubernetes_version" {
  description = "Kubernetes version. Leave null to use the AKS default supported version."
  type        = string
  default     = null
}

variable "node_vm_size" {
  description = "VM size for the system node pool."
  type        = string
  default     = "Standard_D2s_v5"
}

variable "node_count" {
  description = "Number of nodes in the system node pool."
  type        = number
  default     = 3
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default = {
    project     = "aks-opa-policy-demo"
    environment = "demo"
    managed_by  = "terraform"
  }
}
