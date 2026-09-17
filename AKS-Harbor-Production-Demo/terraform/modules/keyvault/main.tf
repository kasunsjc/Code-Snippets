locals {
  # Key Vault names are capped at 24 characters.
  kv_name_prefix = substr(replace(lower("${var.project}${var.environment}"), "/[^a-z0-9]/", ""), 0, 10)
}

resource "azurerm_key_vault" "this" {
  name                          = "kv-${local.kv_name_prefix}-${random_string.suffix.result}"
  location                      = var.location
  resource_group_name           = var.resource_group_name
  tenant_id                     = var.tenant_id
  sku_name                      = "standard"
  rbac_authorization_enabled    = true
  purge_protection_enabled      = true
  public_network_access_enabled = false
  soft_delete_retention_days    = 90
  tags                          = var.tags
}

resource "azurerm_private_endpoint" "vault" {
  name                = "pe-kv-${var.project}-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.privatelink_subnet_id

  private_service_connection {
    name                           = "vault-psc"
    private_connection_resource_id = azurerm_key_vault.this.id
    is_manual_connection           = false
    subresource_names              = ["vault"]
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [var.private_dns_zone_id]
  }
}

resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
  numeric = true
}

resource "azurerm_role_assignment" "secret_user" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = var.kv_csi_identity_object_id
}

resource "azurerm_role_assignment" "secret_officer" {
  count                = var.user_object_id == "" ? 0 : 1
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = var.user_object_id
}

resource "azurerm_key_vault_secret" "harbor_admin_password" {
  name         = "harbor-admin-password"
  value        = var.harbor_admin_password
  key_vault_id = azurerm_key_vault.this.id
}

resource "azurerm_key_vault_secret" "harbor_postgres_password" {
  name         = "harbor-postgres-password"
  value        = var.postgres_password
  key_vault_id = azurerm_key_vault.this.id
}

resource "azurerm_key_vault_secret" "harbor_redis_key" {
  name         = "harbor-redis-key"
  value        = var.redis_password
  key_vault_id = azurerm_key_vault.this.id
}

resource "azurerm_key_vault_secret" "harbor_secret_key" {
  name         = "harbor-secret-key"
  value        = var.harbor_secret_key
  key_vault_id = azurerm_key_vault.this.id
}

resource "azurerm_key_vault_secret" "harbor_core_secret" {
  name         = "harbor-core-secret"
  value        = var.harbor_core_secret
  key_vault_id = azurerm_key_vault.this.id
}

resource "azurerm_key_vault_secret" "harbor_core_xsrf_key" {
  name         = "harbor-core-xsrf-key"
  value        = var.harbor_core_xsrf_key
  key_vault_id = azurerm_key_vault.this.id
}

resource "azurerm_key_vault_secret" "harbor_jobservice_secret" {
  name         = "harbor-jobservice-secret"
  value        = var.harbor_jobservice_secret
  key_vault_id = azurerm_key_vault.this.id
}

resource "azurerm_key_vault_secret" "harbor_registry_http_secret" {
  name         = "harbor-registry-http-secret"
  value        = var.harbor_registry_http_secret
  key_vault_id = azurerm_key_vault.this.id
}

resource "azurerm_key_vault_secret" "harbor_registry_passwd" {
  name         = "harbor-registry-passwd"
  value        = var.harbor_registry_passwd
  key_vault_id = azurerm_key_vault.this.id
}

resource "azurerm_key_vault_secret" "harbor_registry_htpasswd" {
  name         = "harbor-registry-htpasswd"
  value        = var.harbor_registry_htpasswd
  key_vault_id = azurerm_key_vault.this.id
}
