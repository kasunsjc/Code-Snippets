output "resource_group_name" {
  value = azurerm_resource_group.this.name
}

output "node_resource_group_name" {
  value = "rg-${local.name_prefix}-nodes"
}

output "aks_cluster_name" {
  value = "aks-${local.name_prefix}"
}

output "subscription_id" {
  value = data.azurerm_client_config.current.subscription_id
}

output "cluster_id" {
  value = azurerm_kubernetes_cluster.this.id
}

output "portal_url" {
  value = "https://portal.azure.com/#resource${azurerm_kubernetes_cluster.this.id}/overview"
}
