variable "subscription_id" {
  description = "Azure subscription ID in which to provision the demo."
  type        = string
}

variable "location" {
  description = "Azure region for the demo resources."
  type        = string
  default     = "northeurope"
}

variable "resource_group_name" {
  description = "Resource group owned by this demo."
  type        = string
  default     = "rg-k6-demo-dev"
}

variable "cluster_name" {
  description = "Name of the AKS cluster."
  type        = string
  default     = "aks-k6-demo-dev"
}

variable "node_resource_group_name" {
  description = "Custom resource group for AKS-managed nodes and load balancer resources."
  type        = string
  default     = "rg-k6-demo-dev-nodes"
}

variable "kubernetes_version" {
  description = "Supported AKS Kubernetes version; null uses the regional default."
  type        = string
  default     = null
}

variable "node_vm_size" {
  description = "Node VM size; choose one available within your regional quota."
  type        = string
  default     = "Standard_D2s_v5"
}

variable "node_count" {
  description = "Number of nodes shared by the sample API and optional k6 runners."
  type        = number
  default     = 2

  validation {
    condition     = var.node_count >= 1 && floor(var.node_count) == var.node_count
    error_message = "node_count must be a positive integer."
  }
}

variable "tags" {
  description = "Tags applied to the demo infrastructure."
  type        = map(string)
  default = {
    project     = "aks-k6-load-testing"
    environment = "dev"
    managed_by  = "terraform"
  }
}