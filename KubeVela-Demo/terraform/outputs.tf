output "cluster_name" {
  description = "Name of the AKS cluster."
  value       = azurerm_kubernetes_cluster.this.name
}

output "resource_group_name" {
  description = "Name of the AKS resource group."
  value       = azurerm_resource_group.this.name
}

output "oidc_issuer_url" {
  description = "OIDC issuer URL for workload identity configurations."
  value       = azurerm_kubernetes_cluster.this.oidc_issuer_url
}