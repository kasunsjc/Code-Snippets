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
