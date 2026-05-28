variable "key_vault_name" {
  description = "Name of the Key Vault."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group."
  type        = string
}

variable "tenant_id" {
  description = "Azure AD tenant ID."
  type        = string
}

variable "deployer_object_id" {
  description = "Object ID of the Terraform deployer principal (for certificate import RBAC)."
  type        = string
}

variable "app_routing_object_id" {
  description = "Object ID of the AKS App Routing managed identity (for Key Vault Secrets User role)."
  type        = string
}

variable "certificate_name" {
  description = "Name of the certificate in Key Vault."
  type        = string
}

variable "certificate_pfx_base64" {
  description = "Base64-encoded PFX certificate contents."
  type        = string
  sensitive   = true
}

variable "certificate_pfx_password" {
  description = "Password for the PFX file."
  type        = string
  default     = ""
  sensitive   = true
}

variable "aks_cluster_name" {
  description = "Name of the AKS cluster (for approuting attach command)."
  type        = string
}

variable "aks_resource_group_name" {
  description = "Resource group of the AKS cluster (for approuting attach command)."
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources."
  type        = map(string)
  default     = {}
}
