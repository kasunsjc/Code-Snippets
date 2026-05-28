output "resource_group_name" {
  value = azurerm_resource_group.this.name
}

output "aks_cluster_name" {
  value = azurerm_kubernetes_cluster.this.name
}

output "aks_get_credentials_command" {
  value = "az aks get-credentials --resource-group ${azurerm_resource_group.this.name} --name ${azurerm_kubernetes_cluster.this.name} --overwrite-existing"
}

output "key_vault_name" {
  value = azurerm_key_vault.this.name
}

output "key_vault_certificate_uri" {
  description = "Versioned certificate URI to reference in Ingress annotations."
  value       = azurerm_key_vault_certificate.ingress.versionless_secret_id
}

output "argocd_hostname" {
  value = var.argocd_hostname
}

output "argocd_entra_application_client_id" {
  value = azuread_application.argocd.client_id
}

output "argocd_entra_application_object_id" {
  value = azuread_application.argocd.object_id
}

output "argocd_entra_application_tenant_id" {
  value = data.azurerm_client_config.current.tenant_id
}

output "argocd_initial_admin_password_command" {
  description = "Read the Argo CD bootstrap admin password from the cluster. SSO users should be used instead once configured."
  value       = "kubectl -n ${local.argocd_namespace} get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
}
