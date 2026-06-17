output "client_id" {
  description = "Client ID of the managed identity — annotate the Kubernetes Service Account with this."
  value       = azurerm_user_assigned_identity.this.client_id
}

output "principal_id" {
  value = azurerm_user_assigned_identity.this.principal_id
}

output "identity_id" {
  value = azurerm_user_assigned_identity.this.id
}
