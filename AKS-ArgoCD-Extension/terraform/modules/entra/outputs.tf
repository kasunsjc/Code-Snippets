output "application_client_id" {
  description = "Client ID of the Entra ID application."
  value       = azuread_application.argocd.client_id
}

output "application_object_id" {
  description = "Object ID of the Entra ID application."
  value       = azuread_application.argocd.object_id
}

output "client_secret" {
  description = "Client secret value for Argo CD SSO."
  value       = azuread_application_password.argocd.value
  sensitive   = true
}

output "service_principal_id" {
  description = "Object ID of the service principal."
  value       = azuread_service_principal.argocd.id
}
