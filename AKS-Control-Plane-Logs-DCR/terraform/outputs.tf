output "subscription_id" {
  description = "Subscription owning this deployment; scripts use it rather than the CLI default."
  value       = split("/", azurerm_resource_group.this.id)[2]
}

output "resource_group_name" {
  description = "Dedicated demo resource group."
  value       = azurerm_resource_group.this.name
}

output "node_resource_group_name" {
  description = "AKS-managed node resource group, removed when AKS is destroyed."
  value       = azurerm_kubernetes_cluster.this.node_resource_group
}

output "cluster_name" {
  description = "Demo AKS cluster name."
  value       = azurerm_kubernetes_cluster.this.name
}

output "cluster_id" {
  description = "AKS ARM ID used to scope verification queries."
  value       = azurerm_kubernetes_cluster.this.id
}

output "baseline_workspace_customer_id" {
  description = "Baseline workspace customer ID for the Logs query API."
  value       = azurerm_log_analytics_workspace.this["baseline"].workspace_id
}

output "transformed_workspace_customer_id" {
  description = "Transformed workspace customer ID for the Logs query API."
  value       = azurerm_log_analytics_workspace.this["transformed"].workspace_id
}

output "transformed_workspace_resource_id" {
  description = "ARM ID of the transformed workspace."
  value       = azurerm_log_analytics_workspace.this["transformed"].id
}

output "transformation_dcr_id" {
  description = "Workspace transformation DCR ARM ID."
  value       = azurerm_monitor_data_collection_rule.transform.id
}
