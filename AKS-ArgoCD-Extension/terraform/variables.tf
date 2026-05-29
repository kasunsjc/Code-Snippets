variable "project" {
  description = "Short project name used in resource names."
  type        = string
  default     = "argocd"
}

variable "environment" {
  description = "Environment short name (e.g. dev, demo, prod)."
  type        = string
  default     = "demo"
}

variable "location" {
  description = "Azure region."
  type        = string
  default     = "northeurope"
}

variable "kubernetes_version" {
  description = "AKS Kubernetes version."
  type        = string
  default     = "1.31"
}

variable "node_count" {
  description = "Default node pool node count."
  type        = number
  default     = 2
}

variable "node_vm_size" {
  description = "Default node pool VM size."
  type        = string
  default     = "Standard_D4ds_v5"
}

# --- User node pool -----------------------------------------------------------

variable "user_node_pool_name" {
  description = "Name of the user node pool."
  type        = string
  default     = "user"
}

variable "user_node_pool_vm_size" {
  description = "VM size for the user node pool."
  type        = string
  default     = "Standard_D4ds_v5"
}

variable "user_node_pool_node_count" {
  description = "Node count for the user node pool."
  type        = number
  default     = 2
}

# --- Ingress / DNS / Certificate ----------------------------------------------

variable "dns_zone_name" {
  description = "Existing public Azure DNS zone used for Argo CD and sample app ingress (e.g. example.com)."
  type        = string
}

variable "dns_zone_resource_group" {
  description = "Resource group containing the existing Azure DNS zone."
  type        = string
}

variable "argocd_hostname" {
  description = "FQDN exposed for the Argo CD server, must be a record under dns_zone_name."
  type        = string
}

variable "certificate_pfx_path" {
  description = "Path to a .pfx certificate file that covers argocd_hostname; imported into Key Vault for ingress TLS."
  type        = string
}

variable "certificate_pfx_password" {
  description = "Password for the .pfx file. Leave empty if the pfx has no password."
  type        = string
  default     = ""
  sensitive   = true
}

# --- Entra ID SSO -------------------------------------------------------------

variable "extra_redirect_uris" {
  description = "Additional reply URLs to register on the Entra ID app (optional)."
  type        = list(string)
  default     = []
}
