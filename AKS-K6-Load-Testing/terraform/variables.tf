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
  description = "Number of nodes shared by httpbin, Traefik, and optional k6 runners."
  type        = number
  default     = 2

  validation {
    condition     = var.node_count >= 1 && floor(var.node_count) == var.node_count
    error_message = "node_count must be a positive integer."
  }
}

variable "dns_zone_name" {
  description = "Existing, publicly delegated Azure DNS zone; never created or deleted by this demo."
  type        = string
  default     = "kasunrajapakse.xyz"
}

variable "dns_zone_resource_group" {
  description = "Resource group containing the existing DNS zone in the same subscription."
  type        = string
  default     = "rg-dns-zones"
}

variable "httpbin_subdomain" {
  description = "DNS record owned by this demo within the existing zone."
  type        = string
  default     = "httpbin"

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$", var.httpbin_subdomain))
    error_message = "httpbin_subdomain must be a single valid lowercase DNS label."
  }
}

variable "acme_email" {
  description = "Contact email for the Let's Encrypt ACME account."
  type        = string
  default     = "contact@kasunrajapakse.xyz"
}

variable "grafana_admin_object_id" {
  description = "Entra object ID receiving Grafana Admin; deploy.sh detects the signed-in user if empty."
  type        = string
  default     = ""
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