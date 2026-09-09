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

# --- Microsoft Entra ID OIDC SSO for Harbor -----------------------------------
# Terraform creates the Entra ID app registration/SPN, client secret, and Harbor
# role groups; set to false to fall back to Harbor's local admin/password auth.

variable "enable_oidc_auth" {
  description = "Create the Entra ID app registration, groups, and Harbor OIDC config."
  type        = bool
  default     = true
}

variable "harbor_oidc_app_display_name" {
  description = "Display name of the Entra ID application used as Harbor's OIDC client."
  type        = string
  default     = "harbor-oidc-sso"
}

variable "harbor_admin_group_name" {
  description = "Entra ID security group mapped to Harbor's global system admin role (matched by object ID via oidc_admin_group)."
  type        = string
  default     = "harbor-admins"
}

variable "harbor_maintainer_group_name" {
  description = "Entra ID security group for Harbor project Maintainers (assign to a project manually after deploy)."
  type        = string
  default     = "harbor-maintainers"
}

variable "harbor_projectadmin_group_name" {
  description = "Entra ID security group for Harbor project ProjectAdmins (assign to a project manually after deploy)."
  type        = string
  default     = "harbor-projectadmins"
}

variable "harbor_developer_group_name" {
  description = "Entra ID security group for Harbor project Developers (assign to a project manually after deploy)."
  type        = string
  default     = "harbor-developers"
}

variable "harbor_guest_group_name" {
  description = "Entra ID security group for Harbor project Guests, read-only (assign to a project manually after deploy)."
  type        = string
  default     = "harbor-guests"
}

variable "harbor_limited_guest_group_name" {
  description = "Entra ID security group for Harbor project Limited Guests, pull-only with no logs/member visibility (assign to a project manually after deploy)."
  type        = string
  default     = "harbor-limited-guests"
}

variable "harbor_admin_group_member_upns" {
  description = "User principal names added as initial members of the harbor-admins Entra ID group."
  type        = list(string)
  default     = []
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
