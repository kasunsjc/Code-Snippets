output "cluster_id" {
  description = "Resource ID of the AKS cluster."
  value       = azurerm_kubernetes_cluster.this.id
}

output "cluster_name" {
  description = "Name of the AKS cluster."
  value       = azurerm_kubernetes_cluster.this.name
}

output "web_app_routing_object_id" {
  description = "Object ID of the App Routing managed identity."
  value       = azurerm_kubernetes_cluster.this.web_app_routing[0].web_app_routing_identity[0].object_id
}

output "oidc_issuer_url" {
  description = "OIDC issuer URL for the AKS cluster (used for federated identity credentials)."
  value       = azurerm_kubernetes_cluster.this.oidc_issuer_url
}
