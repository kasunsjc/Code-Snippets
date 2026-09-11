variable "resource_group_name" {
  description = "Name of the resource group that hosts the AKS cluster."
  type        = string
  default     = "rg-aks-node-autoprovision"
}

variable "location" {
  description = "Azure region for all resources."
  type        = string
  default     = "northeurope"
}

variable "cluster_name" {
  description = "Name of the AKS cluster."
  type        = string
  default     = "aks-node-autoprovision"
}

variable "kubernetes_version" {
  description = "Kubernetes version for the cluster. Leave null to use the latest recommended GA version."
  type        = string
  default     = null
}

variable "system_node_vm_size" {
  description = "VM size for the required system node pool (NAP only manages the extra, workload-facing capacity)."
  type        = string
  default     = "Standard_D4s_v5"
}

variable "system_node_count" {
  description = "Fixed node count for the system node pool."
  type        = number
  default     = 1
}

variable "node_provisioning_default_pools" {
  description = "Whether AKS should create the default NAP NodePools (default/system-surge). Possible values: Auto, None."
  type        = string
  default     = "Auto"

  validation {
    condition     = contains(["Auto", "None"], var.node_provisioning_default_pools)
    error_message = "node_provisioning_default_pools must be either 'Auto' or 'None'."
  }
}

variable "log_retention_days" {
  description = "Retention in days for the Log Analytics workspace used to capture NAP/Karpenter control plane logs."
  type        = number
  default     = 30
}

variable "user_object_id" {
  description = "Optional Entra ID object ID of the current user, granted the Azure Kubernetes Service RBAC Cluster Admin role for convenience."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default = {
    project     = "aks-node-autoprovision"
    environment = "demo"
    managed_by  = "terraform"
  }
}
