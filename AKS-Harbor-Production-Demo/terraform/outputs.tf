output "resource_group_name" {
  value = azurerm_resource_group.this.name
}

output "cluster_name" {
  value = local.cluster_name
}

output "subscription_id" {
  value = data.azurerm_client_config.current.subscription_id
}

output "tenant_id" {
  value = data.azurerm_client_config.current.tenant_id
}

output "harbor_fqdn" {
  value = local.harbor_fqdn
}

output "harbor_subdomain" {
  value = var.harbor_subdomain
}

output "dns_zone_name" {
  value = var.dns_zone_name
}

output "dns_zone_resource_group" {
  value = var.dns_zone_resource_group
}

output "acme_email" {
  value = var.acme_email
}

output "grafana_endpoint" {
  value = azurerm_dashboard_grafana.this.endpoint
}

output "log_analytics_workspace_name" {
  value = azurerm_log_analytics_workspace.this.name
}

output "harbor_admin_password" {
  value     = random_password.harbor_admin.result
  sensitive = true
}

output "cert_manager_client_id" {
  value = module.identity.client_id
}

output "key_vault_name" {
  value = module.keyvault.name
}

output "kv_csi_client_id" {
  value = module.aks.key_vault_identity_client_id
}

output "postgres_host" {
  value = module.postgres.server_fqdn
}

output "postgres_password" {
  value     = module.postgres.postgres_password
  sensitive = true
}

output "redis_host" {
  value = module.redis.host
}

output "redis_port" {
  value = module.redis.port
}

output "redis_password" {
  value     = module.redis.redis_password
  sensitive = true
}

output "enable_oidc_auth" {
  value = module.identity.enable_oidc_auth
}

output "harbor_oidc_client_id" {
  value = module.identity.harbor_oidc_client_id
}

output "harbor_oidc_client_secret" {
  value     = module.identity.harbor_oidc_client_secret
  sensitive = true
}

output "harbor_oidc_tenant_id" {
  value = module.identity.harbor_oidc_tenant_id
}

output "harbor_oidc_endpoint" {
  value = module.identity.harbor_oidc_endpoint
}

output "harbor_oidc_redirect_uri" {
  value = module.identity.harbor_oidc_redirect_uri
}

output "harbor_admin_group_object_id" {
  value = module.identity.harbor_admin_group_object_id
}

output "harbor_projectadmin_group_object_id" {
  value = module.identity.harbor_projectadmin_group_object_id
}

output "harbor_maintainer_group_object_id" {
  value = module.identity.harbor_maintainer_group_object_id
}

output "harbor_developer_group_object_id" {
  value = module.identity.harbor_developer_group_object_id
}

output "harbor_guest_group_object_id" {
  value = module.identity.harbor_guest_group_object_id
}

output "harbor_limited_guest_group_object_id" {
  value = module.identity.harbor_limited_guest_group_object_id
}

output "bastion_name" {
  value = module.bastion.bastion_name
}

output "jumpbox_vm_id" {
  value = module.bastion.jumpbox_vm_id
}

output "jumpbox_private_ip" {
  value = module.bastion.jumpbox_private_ip
}

output "jumpbox_admin_username" {
  value = module.bastion.jumpbox_admin_username
}

output "jumpbox_admin_password" {
  value     = module.bastion.jumpbox_admin_password
  sensitive = true
}

