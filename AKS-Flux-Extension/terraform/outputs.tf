output "resource_group_name" {
  description = "Resource group containing the demo."
  value       = azurerm_resource_group.this.name
}

output "cluster_name" {
  description = "AKS cluster name."
  value       = azurerm_kubernetes_cluster.this.name
}

output "node_resource_group_name" {
  description = "AKS-managed resource group, also deleted with the cluster."
  value       = azurerm_kubernetes_cluster.this.node_resource_group
}

output "flux_configuration_name" {
  description = "Azure Flux configuration name."
  value       = contains(var.enabled_demos, "kustomize") ? azurerm_kubernetes_flux_configuration.this[0].name : ""
}

output "helm_flux_configuration_name" {
  description = "Separate Azure Flux configuration for the Helm demo, when enabled."
  value       = contains(var.enabled_demos, "helm") ? azurerm_kubernetes_flux_configuration.kubeplay[0].name : ""
}

output "enabled_demos" {
  description = "Demo selection used by the last Terraform apply."
  value       = var.enabled_demos
}