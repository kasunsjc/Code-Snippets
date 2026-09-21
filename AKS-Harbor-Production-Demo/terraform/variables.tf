variable "project" {
  description = "Short project name used to build Azure resource names."
  type        = string
  default     = "harborprod"
}

variable "environment" {
  description = "Environment name used in naming conventions."
  type        = string
  default     = "demo"
}

variable "location" {
  description = "Azure region for the resources."
  type        = string
  default     = "northeurope"
}

variable "kubernetes_version" {
  description = "AKS Kubernetes version to deploy."
  type        = string
  default     = null
}

variable "dns_zone_name" {
  description = "Existing Azure DNS zone name, for example example.com."
  type        = string
}

variable "dns_zone_resource_group" {
  description = "Resource group that contains the existing Azure DNS zone."
  type        = string
}

variable "harbor_subdomain" {
  description = "Harbor DNS subdomain name."
  type        = string
  default     = "harbor"
}

variable "acme_email" {
  description = "Email used for the cert-manager ACME account."
  type        = string
}

variable "user_object_id" {
  description = "Optional Entra object ID for Grafana admin rights or RBAC grants."
  type        = string
  default     = ""
}

variable "enable_oidc_auth" {
  description = "Create the Entra ID application, client secret, role groups, and Harbor OIDC configuration."
  type        = bool
  default     = true
}

variable "harbor_oidc_app_display_name" {
  description = "Display name of the Entra ID application used by Harbor for OIDC login."
  type        = string
  default     = "harbor-oidc-sso"
}

variable "harbor_admin_group_name" {
  description = "Entra security group mapped to Harbor's global system administrator role."
  type        = string
  default     = "harbor-admins"
}

variable "harbor_projectadmin_group_name" {
  description = "Entra security group for Harbor project administrators."
  type        = string
  default     = "harbor-projectadmins"
}

variable "harbor_maintainer_group_name" {
  description = "Entra security group for Harbor project maintainers."
  type        = string
  default     = "harbor-maintainers"
}

variable "harbor_developer_group_name" {
  description = "Entra security group for Harbor project developers."
  type        = string
  default     = "harbor-developers"
}

variable "harbor_guest_group_name" {
  description = "Entra security group for Harbor project guests."
  type        = string
  default     = "harbor-guests"
}

variable "harbor_limited_guest_group_name" {
  description = "Entra security group for Harbor project limited guests."
  type        = string
  default     = "harbor-limited-guests"
}

variable "harbor_admin_group_member_upns" {
  description = "User principal names added as initial members of the Harbor administrators group."
  type        = list(string)
  default     = []
}

variable "jumpbox_ssh_public_key" {
  description = "SSH public key (e.g. contents of id_ed25519.pub) authorized on the Bastion-only jumpbox VM."
  type        = string
}

variable "jumpbox_admin_username" {
  description = "Admin username for the jumpbox VM."
  type        = string
  default     = "azureuser"
}

variable "jumpbox_vm_size" {
  description = "VM size for the jumpbox used to reach the private AKS API server via Azure Bastion."
  type        = string
  default     = "Standard_B2s"
}

variable "tags" {
  description = "Tags applied to Azure resources."
  type        = map(string)
  default = {
    project    = "harbor-prod"
    demo       = "harbor-production-demo"
    managed_by = "terraform"
  }
}
