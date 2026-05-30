variable "cluster_id" {
  description = "Resource ID of the AKS cluster."
  type        = string
}

variable "argocd_namespace" {
  description = "Namespace where Argo CD will be installed."
  type        = string
  default     = "argocd"
}

variable "tenant_id" {
  description = "Microsoft Entra tenant ID."
  type        = string
}

variable "client_id" {
  description = "Entra ID application client ID for SSO."
  type        = string
}

variable "workload_identity_client_id" {
  description = "Client ID of the user-assigned managed identity used for Argo CD workload identity (Azure resource access)."
  type        = string
}

variable "argocd_hostname" {
  description = "FQDN exposed for the Argo CD server."
  type        = string
}

variable "admin_group_object_id" {
  description = "Object ID of the Entra group whose members become Argo CD admins."
  type        = string
}

variable "entra_service_principal_id" {
  description = "ID of the Entra service principal (used for depends_on ordering)."
  type        = string
  default     = ""
}

variable "keyvault_ready" {
  description = "Sentinel value — pass any output from the keyvault module to enforce ordering."
  type        = string
  default     = ""
}
