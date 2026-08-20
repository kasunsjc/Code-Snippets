output "resource_group_name" {
  description = "Resource group containing the demo resources."
  value       = azurerm_resource_group.this.name
}

output "cluster_name" {
  description = "AKS cluster name."
  value       = azurerm_kubernetes_cluster.this.name
}

output "cluster_fqdn" {
  description = "FQDN of the AKS API server."
  value       = azurerm_kubernetes_cluster.this.fqdn
}

output "network_data_plane" {
  description = "Network data plane in use (should be cilium)."
  value       = azurerm_kubernetes_cluster.this.network_profile[0].network_data_plane
}

output "grafana_endpoint" {
  description = "Azure Managed Grafana endpoint URL."
  value       = azurerm_dashboard_grafana.this.endpoint
}

output "monitor_workspace_id" {
  description = "Azure Monitor workspace (Managed Prometheus) resource ID."
  value       = azurerm_monitor_workspace.this.id
}

output "get_credentials_command" {
  description = "Command to fetch kubeconfig credentials."
  value       = "az aks get-credentials --resource-group ${azurerm_resource_group.this.name} --name ${azurerm_kubernetes_cluster.this.name}"
}
