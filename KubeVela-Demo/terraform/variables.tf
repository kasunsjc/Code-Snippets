variable "location" {
  description = "Azure region for the demo resources."
  type        = string
  default     = "eastus"
}

variable "resource_group_name" {
  description = "Resource group that contains the AKS cluster."
  type        = string
  default     = "rg-kubevela-demo-dev"
}

variable "cluster_name" {
  description = "Name of the AKS cluster."
  type        = string
  default     = "kubevela-demo-aks"
}

variable "node_resource_group_name" {
  description = "Resource group managed by AKS for node infrastructure."
  type        = string
  default     = "rg-kubevela-demo-dev-nodes"
}

variable "node_vm_size" {
  description = "VM size for each demo node."
  type        = string
  default     = "Standard_D2as_v5"
}

variable "node_count" {
  description = "Number of nodes for the demo cluster."
  type        = number
  default     = 2
}

variable "tags" {
  description = "Tags applied to Azure resources."
  type        = map(string)
  default = {
    environment = "demo"
    workload    = "kubevela"
  }
}