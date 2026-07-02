variable "resource_group_name" {
  description = "Resource group name for the demo deployment."
  type        = string
  default     = "rg-aks-keda-demo"
}

variable "location" {
  description = "Azure region for all resources."
  type        = string
  default     = "northeurope"
}

variable "cluster_name" {
  description = "AKS cluster name."
  type        = string
  default     = "aks-keda-demo"
}

variable "kubernetes_version" {
  description = "AKS Kubernetes version."
  type        = string
  default     = "1.35"
}

variable "node_count" {
  description = "System node pool node count."
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
  description = "Minimum node count for AKS system node pool when autoscaling is enabled."
  type        = number
  default     = 1
}

variable "node_max_count" {
  description = "Maximum node count for AKS system node pool when autoscaling is enabled."
  type        = number
  default     = 5
}

variable "user_object_id" {
  description = "Optional Entra ID object ID for Grafana Admin and AKS RBAC Cluster Admin role assignments."
  type        = string
  default     = ""
}

variable "acr_name" {
  description = "Optional ACR name. If empty, a unique name is generated."
  type        = string
  default     = ""
}

variable "acr_sku" {
  description = "ACR SKU."
  type        = string
  default     = "Basic"

  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.acr_sku)
    error_message = "acr_sku must be one of: Basic, Standard, Premium."
  }
}

variable "checkpoint_container_name" {
  description = "Blob container name used by Event Hub consumer checkpoints."
  type        = string
  default     = "eventhub-checkpoints"
}

variable "eventhub_partition_count" {
  description = "Number of partitions for the Event Hub used by Scenario 05."
  type        = number
  default     = 20
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default = {
    Environment = "Demo"
    Project     = "AKS-KEDA"
    ManagedBy   = "Terraform"
  }
}
