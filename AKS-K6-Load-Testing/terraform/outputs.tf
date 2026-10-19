output "subscription_id" {
  description = "Subscription containing the demo, used by deploy and cleanup scripts."
  value       = var.subscription_id
}

output "resource_group_name" {
  description = "Resource group containing the AKS cluster."
  value       = azurerm_resource_group.demo.name
}

output "cluster_name" {
  description = "AKS cluster name used to retrieve kubeconfig."
  value       = azurerm_kubernetes_cluster.demo.name
}

output "node_resource_group_name" {
  description = "AKS-managed resource group containing nodes, networking, and service public IPs."
  value       = azurerm_kubernetes_cluster.demo.node_resource_group
}

output "cluster_id" {
  description = "Azure resource ID of the AKS cluster."
  value       = azurerm_kubernetes_cluster.demo.id
}