output "resource_group_name" {
  value = azurerm_resource_group.this.name
}

output "aks_cluster_name" {
  value = module.aks.cluster_name
}

output "aks_get_credentials_command" {
  value = "az aks get-credentials --resource-group ${azurerm_resource_group.this.name} --name ${module.aks.cluster_name} --overwrite-existing"
}

output "key_vault_name" {
  value = module.keyvault.key_vault_name
}

output "key_vault_certificate_uri" {
  description = "Versionless certificate URI to reference in Ingress annotations."
  value       = module.keyvault.certificate_versionless_secret_id
}

output "argocd_hostname" {
  value = var.argocd_hostname
}

output "argocd_entra_application_client_id" {
  value = module.entra.application_client_id
}

output "argocd_entra_application_object_id" {
  value = module.entra.application_object_id
}

output "argocd_entra_application_tenant_id" {
  value = data.azurerm_client_config.current.tenant_id
}

output "argocd_admin_group_object_id" {
  description = "Object ID of the argocd-admins Entra ID security group."
  value       = module.entra.admin_group_object_id
}

output "argocd_initial_admin_password_command" {
  description = "Read the Argo CD bootstrap admin password from the cluster."
  value       = "kubectl -n ${local.argocd_namespace} get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
}

output "argocd_extension_id" {
  description = "Resource ID of the Argo CD cluster extension."
  value       = module.argocd_extension.extension_id
}

output "argocd_workload_identity_client_id" {
  description = "Client ID of the ArgoCD workload identity — annotate ArgoCD service accounts with this value."
  value       = azurerm_user_assigned_identity.argocd.client_id
}

output "argocd_workload_identity_principal_id" {
  description = "Principal ID of the ArgoCD workload identity managed identity."
  value       = azurerm_user_assigned_identity.argocd.principal_id
}
