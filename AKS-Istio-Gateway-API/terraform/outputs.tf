output "resource_group_name" {
  description = "Name of the resource group"
  value       = azurerm_resource_group.rg.name
}

output "cluster_name" {
  description = "Name of the AKS cluster"
  value       = var.cluster_name
}

output "cluster_id" {
  description = "ID of the AKS cluster"
  value       = azapi_resource.aks.id
}

output "cluster_fqdn" {
  description = "FQDN of the AKS cluster"
  value       = jsondecode(azapi_resource.aks.output).properties.fqdn
}

output "kube_config_command" {
  description = "Command to get kubeconfig"
  value       = "az aks get-credentials --resource-group ${azurerm_resource_group.rg.name} --name ${var.cluster_name}"
}

output "gateway_class" {
  description = "Gateway class to use in Kubernetes manifests"
  value       = "approuting-istio"
}
