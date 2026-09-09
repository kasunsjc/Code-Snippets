variable "project" {
  description = "Short project name used to build resource names (e.g. rg-<project>-<environment>)."
  type        = string
  default     = "harbor"
}

variable "environment" {
  description = "Environment name used to build resource names (e.g. demo, dev)."
  type        = string
  default     = "demo"
}

variable "location" {
  description = "Azure region for all resources."
  type        = string
  default     = "northeurope"
}

variable "kubernetes_version" {
  description = "AKS Kubernetes version. Leave null to use the default supported version in the region."
  type        = string
  default     = null
}

variable "node_vm_size" {
  description = "VM size for the AKS system node pool. Harbor's bundled core/registry/jobservice/portal/trivy/redis/postgresql components need more than a burstable 2 vCPU size."
  type        = string
  default     = "Standard_D4s_v3"
}

variable "node_count" {
  description = "Initial node count for the AKS system node pool."
  type        = number
  default     = 2
}

variable "node_min_count" {
  description = "Minimum node count for cluster autoscaling."
  type        = number
  default     = 2
}

variable "node_max_count" {
  description = "Maximum node count for cluster autoscaling."
  type        = number
  default     = 4
}

variable "dns_zone_name" {
  description = "Name of an EXISTING Azure DNS zone (e.g. example.com) that is already delegated to Azure DNS. This demo does not create the zone."
  type        = string
}

variable "dns_zone_resource_group" {
  description = "Resource group that contains the existing Azure DNS zone."
  type        = string
}

variable "harbor_subdomain" {
  description = "Subdomain Harbor is exposed on, combined with dns_zone_name (e.g. harbor-demo -> harbor-demo.example.com)."
  type        = string
  default     = "harbor-demo"
}

variable "acme_email" {
  description = "Contact email registered with Let's Encrypt for the production ACME account."
  type        = string
}

variable "user_object_id" {
  description = "Optional Microsoft Entra ID object ID to grant the Grafana Admin role to (e.g. your own signed-in user). Leave empty to skip."
  type        = string
  default     = ""
}

# --- Reserved for a future demo: Azure AD (Microsoft Entra ID) OIDC SSO for Harbor ---
# Not used by this iteration's Terraform or Helm values; kept here so the follow-up
# demo only needs `-var` overrides instead of new variable plumbing.

variable "enable_oidc_auth" {
  description = "Reserved for a future demo. Does not change any resource in this iteration."
  type        = bool
  default     = false
}

variable "oidc_client_id" {
  description = "Reserved for a future demo (Entra ID application client ID for Harbor OIDC login). Unused today."
  type        = string
  default     = ""
}

variable "oidc_client_secret" {
  description = "Reserved for a future demo (Entra ID application client secret for Harbor OIDC login). Unused today."
  type        = string
  default     = ""
  sensitive   = true
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default = {
    project    = "harbor"
    demo       = "aks-harbor-registry-demo"
    managed_by = "terraform"
  }
}
