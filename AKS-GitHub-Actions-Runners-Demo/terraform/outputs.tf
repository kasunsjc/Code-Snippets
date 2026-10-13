output "resource_group_name" {
  value = azurerm_resource_group.this.name
}

output "node_resource_group_name" {
  value = element(split("/", azurerm_kubernetes_automatic_cluster.this.node_resource_group_id), 4)
}

output "aks_cluster_name" {
  value = "aks-${local.name_prefix}"
}

output "subscription_id" {
  value = data.azurerm_client_config.current.subscription_id
}

output "cluster_id" {
  value = azurerm_kubernetes_automatic_cluster.this.id
}

output "portal_url" {
  value = "https://portal.azure.com/#resource${azurerm_kubernetes_automatic_cluster.this.id}/overview"
}

output "storage_account_name" {
  value = azurerm_storage_account.runners.name
}

output "cache_share_name" {
  value = azurerm_storage_share.nuget.name
}

output "cache_share_quota_gib" {
  value = var.cache_share_quota_gib
}
