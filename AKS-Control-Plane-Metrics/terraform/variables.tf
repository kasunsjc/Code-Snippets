variable "project" {
  description = "Short project name used to build resource names."
  type        = string
  default     = "cpmetrics"
}

variable "environment" {
  description = "Environment name used to build resource names."
  type        = string
  default     = "demo"
}

variable "location" {
  description = "Azure region for all resources."
  type        = string
  default     = "eastus2"
}

variable "kubernetes_version" {
  description = "Kubernetes version. Leave null for the latest recommended version."
  type        = string
  default     = null
}

variable "node_vm_size" {
  description = "VM size for the system node pool."
  type        = string
  default     = "Standard_D4s_v5"
}

variable "node_count" {
  description = "Number of nodes in the system node pool."
  type        = number
  default     = 2
}

variable "enable_control_plane_metrics" {
  description = "Enable AKS control plane metrics (azureMonitorProfile.metrics.controlPlane.enabled). Set to false to enable it later with 'az aks update --enable-control-plane-metrics'."
  type        = bool
  default     = true
}

variable "grafana_major_version" {
  description = "Azure Managed Grafana major version."
  type        = number
  default     = 12
}

variable "user_object_id" {
  description = "Entra ID object ID of the user to grant the Grafana Admin role. Leave empty to skip."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Additional tags applied to all resources."
  type        = map(string)
  default     = {}
}
