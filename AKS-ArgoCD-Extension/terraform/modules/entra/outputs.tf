output "application_client_id" {
  description = "Client ID of the Entra ID application."
  value       = azuread_application.argocd.client_id
}

output "application_object_id" {
  description = "Object ID of the Entra ID application."
  value       = azuread_application.argocd.object_id
}

output "service_principal_id" {
  description = "Object ID of the service principal."
  value       = azuread_service_principal.argocd.id
}

output "admin_group_object_id" {
  description = "Object ID of the argocd-admins Entra ID security group."
  value       = azuread_group.argocd_admins.object_id
}
