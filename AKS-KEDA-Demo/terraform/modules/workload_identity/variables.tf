variable "name" {
  description = "Name prefix for the user-assigned managed identity."
  type        = string
}

variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "oidc_issuer_url" {
  description = "OIDC issuer URL from the AKS cluster."
  type        = string
}

variable "prometheus_workspace_id" {
  description = "Resource ID of the Azure Managed Prometheus workspace."
  type        = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
