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

# --- Microsoft Entra ID OIDC SSO for Harbor -----------------------------------

output "enable_oidc_auth" {
  value = var.enable_oidc_auth
}

output "harbor_oidc_client_id" {
  value = try(azuread_application.harbor[0].client_id, "")
}

output "harbor_oidc_client_secret" {
  value     = try(azuread_application_password.harbor[0].value, "")
  sensitive = true
}

output "harbor_oidc_tenant_id" {
  value = data.azurerm_client_config.current.tenant_id
}

output "harbor_oidc_endpoint" {
  value = "https://login.microsoftonline.com/${data.azurerm_client_config.current.tenant_id}/v2.0"
}

output "harbor_admin_group_object_id" {
  value = try(azuread_group.harbor_admins[0].object_id, "")
}

output "harbor_projectadmin_group_object_id" {
  value = try(azuread_group.harbor_projectadmins[0].object_id, "")
}

output "harbor_maintainer_group_object_id" {
  value = try(azuread_group.harbor_maintainers[0].object_id, "")
}

output "harbor_developer_group_object_id" {
  value = try(azuread_group.harbor_developers[0].object_id, "")
}

output "harbor_guest_group_object_id" {
  value = try(azuread_group.harbor_guests[0].object_id, "")
}

output "harbor_limited_guest_group_object_id" {
  value = try(azuread_group.harbor_limited_guests[0].object_id, "")
}
