output "resource_group_name" {
  value = azurerm_resource_group.this.name
}

output "cluster_name" {
  value = azurerm_kubernetes_cluster.this.name
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

output "harbor_fqdn" {
  value = local.harbor_fqdn
}

output "harbor_subdomain" {
  value = var.harbor_subdomain
}

output "acme_email" {
  value = var.acme_email
}

# Redirect URI needed to register a future Entra ID application for Harbor OIDC SSO.
output "harbor_oidc_redirect_uri" {
  value = "https://${local.harbor_fqdn}/c/oidc/callback"
}

output "cert_manager_client_id" {
  value = azurerm_user_assigned_identity.cert_manager.client_id
}

output "log_analytics_workspace_id" {
  value = azurerm_log_analytics_workspace.this.id
}

output "log_analytics_workspace_name" {
  value = azurerm_log_analytics_workspace.this.name
}

output "monitor_workspace_id" {
  value = azurerm_monitor_workspace.this.id
}

output "grafana_endpoint" {
  value = azurerm_dashboard_grafana.this.endpoint
}

output "grafana_name" {
  value = azurerm_dashboard_grafana.this.name
}

output "harbor_admin_password" {
  value     = random_password.harbor_admin.result
  sensitive = true
}
