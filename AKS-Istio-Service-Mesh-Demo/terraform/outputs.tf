output "resource_group_name" {
  value = azurerm_resource_group.this.name
}

output "aks_cluster_name" {
  value = azurerm_kubernetes_cluster.this.name
}

output "node_resource_group" {
  value = azurerm_kubernetes_cluster.this.node_resource_group
}

output "aks_get_credentials_command" {
  value = "az aks get-credentials --resource-group ${azurerm_resource_group.this.name} --name ${azurerm_kubernetes_cluster.this.name} --overwrite-existing"
}

output "istio_revisions" {
  description = "Istio control plane revision(s) actually installed by AKS (e.g. asm-1-24)."
  value       = azurerm_kubernetes_cluster.this.service_mesh_profile[0].revisions
}

output "external_ingress_gateway_enabled" {
  value = azurerm_kubernetes_cluster.this.service_mesh_profile[0].external_ingress_gateway_enabled
}

output "internal_ingress_gateway_enabled" {
  value = azurerm_kubernetes_cluster.this.service_mesh_profile[0].internal_ingress_gateway_enabled
}

output "log_analytics_workspace_name" {
  value = var.enable_monitoring ? azurerm_log_analytics_workspace.this[0].name : null
}

output "prometheus_workspace_id" {
  value = var.enable_monitoring ? azurerm_monitor_workspace.this[0].id : null
}

output "grafana_endpoint" {
  value = var.enable_monitoring ? azurerm_dashboard_grafana.this[0].endpoint : null
}

output "subscription_id" {
  value = data.azurerm_client_config.current.subscription_id
}

output "dns_zone_name" {
  value = data.azurerm_dns_zone.this.name
}

output "dns_zone_resource_group" {
  value = var.dns_zone_resource_group
}

output "bookinfo_fqdn" {
  value = local.bookinfo_fqdn
}

output "bookinfo_subdomain" {
  value = var.bookinfo_subdomain
}

output "acme_email" {
  value = var.acme_email
}

output "cert_manager_client_id" {
  value = azurerm_user_assigned_identity.cert_manager.client_id
}
