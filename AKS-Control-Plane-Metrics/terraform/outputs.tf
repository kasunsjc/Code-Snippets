output "resource_group_name" {
  description = "Resource group containing the demo resources."
  value       = azurerm_resource_group.this.name
}

output "node_resource_group_name" {
  description = "AKS node resource group."
  value       = azurerm_kubernetes_cluster.this.node_resource_group
}

output "cluster_name" {
  description = "AKS cluster name."
  value       = azurerm_kubernetes_cluster.this.name
}

output "monitor_workspace_id" {
  description = "Azure Monitor workspace resource ID."
  value       = azurerm_monitor_workspace.this.id
}

output "prometheus_query_endpoint" {
  description = "Prometheus query endpoint of the Azure Monitor workspace."
  value       = azurerm_monitor_workspace.this.query_endpoint
}

output "grafana_name" {
  description = "Azure Managed Grafana name."
  value       = azurerm_dashboard_grafana.this.name
}

output "grafana_endpoint" {
  description = "Azure Managed Grafana endpoint URL."
  value       = azurerm_dashboard_grafana.this.endpoint
}

output "control_plane_metrics_enabled" {
  description = "Whether Terraform enabled control plane metrics."
  value       = var.enable_control_plane_metrics
}

output "get_credentials_command" {
  description = "Command to fetch kubeconfig credentials."
  value       = "az aks get-credentials --resource-group ${azurerm_resource_group.this.name} --name ${azurerm_kubernetes_cluster.this.name} --overwrite-existing"
}
