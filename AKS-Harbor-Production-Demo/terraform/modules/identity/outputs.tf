output "client_id" {
  value = azurerm_user_assigned_identity.cert_manager.client_id
}

output "principal_id" {
  value = azurerm_user_assigned_identity.cert_manager.principal_id
}

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

output "harbor_oidc_redirect_uri" {
  value = "https://${var.harbor_fqdn}/c/oidc/callback"
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
