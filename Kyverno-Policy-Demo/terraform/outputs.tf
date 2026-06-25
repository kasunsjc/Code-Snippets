output "resource_group_name" {
  description = "Resource group name."
  value       = azurerm_resource_group.this.name
}

output "aks_cluster_name" {
  description = "AKS cluster name."
  value       = module.aks.cluster_name
}

output "aks_cluster_id" {
  description = "AKS cluster resource ID."
  value       = module.aks.cluster_id
}

output "log_analytics_workspace_id" {
  description = "Log Analytics workspace resource ID."
  value       = module.log_analytics.workspace_id
}

output "get_credentials_command" {
  description = "Azure CLI command to configure kubectl."
  value       = "az aks get-credentials --resource-group ${azurerm_resource_group.this.name} --name ${module.aks.cluster_name} --overwrite-existing"
}
