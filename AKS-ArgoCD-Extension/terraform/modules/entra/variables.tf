variable "application_display_name" {
  description = "Display name for the Entra ID application."
  type        = string
}

variable "owner_object_id" {
  description = "Object ID of the Entra ID principal that owns the application."
  type        = string
}

variable "argocd_hostname" {
  description = "FQDN of the Argo CD server (used to build redirect URIs)."
  type        = string
}

variable "extra_redirect_uris" {
  description = "Additional reply URLs to register on the Entra ID app."
  type        = list(string)
  default     = []
}

variable "admin_group_name" {
  description = "Display name for the Entra ID security group whose members become Argo CD admins."
  type        = string
  default     = "argocd-admins"
}

variable "oidc_issuer_url" {
  description = "OIDC issuer URL of the AKS cluster — used to create a federated identity credential on the Entra app so argocd-server can exchange its K8s SA token for an Entra ID token."
  type        = string
}
