output "cluster_name" {
  description = "AKS cluster name."
  value       = azurerm_kubernetes_cluster.this.name
}

output "cluster_id" {
  description = "AKS cluster resource ID."
  value       = azurerm_kubernetes_cluster.this.id
}

output "oidc_issuer_url" {
  description = "AKS OIDC issuer URL for workload identity."
  value       = azurerm_kubernetes_cluster.this.oidc_issuer_url
}

output "kubelet_identity_object_id" {
  description = "Object ID of the kubelet managed identity."
  value       = azurerm_kubernetes_cluster.this.kubelet_identity[0].object_id
}

output "kube_config_raw" {
  description = "Raw kubeconfig content."
  value       = azurerm_kubernetes_cluster.this.kube_config_raw
  sensitive   = true
}
