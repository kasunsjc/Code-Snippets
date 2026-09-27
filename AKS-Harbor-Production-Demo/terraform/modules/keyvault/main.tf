locals {
  # Key Vault names are capped at 24 characters.
  kv_name_prefix = substr(replace(lower("${var.project}${var.environment}"), "/[^a-z0-9]/", ""), 0, 10)
}

# terraform apply writes Key Vault secrets from wherever it's run (not from
# inside the VNet like kubectl/helm), so the vault's data plane needs the
# operator's current public IP allow-listed - everything else stays denied.
data "http" "my_ip" {
  url = "https://ifconfig.me/ip"
}

resource "azurerm_key_vault" "this" {
  name                          = "kv-${local.kv_name_prefix}-${random_string.suffix.result}"
  location                      = var.location
  resource_group_name           = var.resource_group_name
  tenant_id                     = var.tenant_id
  sku_name                      = "standard"
  rbac_authorization_enabled    = true
  purge_protection_enabled      = true
  public_network_access_enabled = true
  soft_delete_retention_days    = 90
  tags                          = var.tags

  network_acls {
    default_action = "Deny"
    bypass         = "AzureServices"
    ip_rules       = [trimspace(data.http.my_ip.response_body)]
  }
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

# The CSI driver authenticates as the node's kubelet identity (useVMManagedIdentity)
# for the harbor-secret-sync pod, since that identity is already attached to every
# node's VMSS - no Workload Identity federation needed.
resource "azurerm_role_assignment" "secret_user_kubelet" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = var.kubelet_identity_object_id
}

resource "azurerm_role_assignment" "secret_officer" {
  count                = var.user_object_id == "" ? 0 : 1
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = var.user_object_id
}

# Whoever runs `terraform apply` writes these secrets, regardless of whether
# user_object_id (a separate, optional grant) is set - so grant it directly.
data "azurerm_client_config" "current" {}

resource "azurerm_role_assignment" "secret_officer_caller" {
  # Skip if the caller is already covered by secret_officer above, to avoid
  # a duplicate/conflicting role assignment for the same principal.
  count                = var.user_object_id == data.azurerm_client_config.current.object_id ? 0 : 1
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

# RBAC role assignments can take a minute to propagate; writing secrets
# immediately after granting the role is a common source of 403s.
resource "time_sleep" "rbac_propagation" {
  create_duration = "90s"

  depends_on = [azurerm_role_assignment.secret_user, azurerm_role_assignment.secret_officer, azurerm_role_assignment.secret_officer_caller]
}

# Key Vault firewall/network-ACL changes can lag a couple of minutes behind
# the ARM update call succeeding - re-waits whenever the allow-listed IP
# changes (e.g. a dynamic/residential ISP re-assigning an address mid-apply).
resource "time_sleep" "network_acl_propagation" {
  create_duration = "90s"

  triggers = {
    ip_rule = trimspace(data.http.my_ip.response_body)
  }

  depends_on = [azurerm_key_vault.this]
}

resource "azurerm_key_vault_secret" "harbor_admin_password" {
  name         = "harbor-admin-password"
  value        = var.harbor_admin_password
  key_vault_id = azurerm_key_vault.this.id
  depends_on   = [time_sleep.rbac_propagation, time_sleep.network_acl_propagation]
}

resource "azurerm_key_vault_secret" "harbor_postgres_password" {
  name         = "harbor-postgres-password"
  value        = var.postgres_password
  key_vault_id = azurerm_key_vault.this.id
  depends_on   = [time_sleep.rbac_propagation, time_sleep.network_acl_propagation]
}

resource "azurerm_key_vault_secret" "harbor_redis_key" {
  name         = "harbor-redis-key"
  value        = var.redis_password
  key_vault_id = azurerm_key_vault.this.id
  depends_on   = [time_sleep.rbac_propagation, time_sleep.network_acl_propagation]
}

resource "azurerm_key_vault_secret" "harbor_secret_key" {
  name         = "harbor-secret-key"
  value        = var.harbor_secret_key
  key_vault_id = azurerm_key_vault.this.id
  depends_on   = [time_sleep.rbac_propagation, time_sleep.network_acl_propagation]
}

resource "azurerm_key_vault_secret" "harbor_core_secret" {
  name         = "harbor-core-secret"
  value        = var.harbor_core_secret
  key_vault_id = azurerm_key_vault.this.id
  depends_on   = [time_sleep.rbac_propagation, time_sleep.network_acl_propagation]
}

resource "azurerm_key_vault_secret" "harbor_core_xsrf_key" {
  name         = "harbor-core-xsrf-key"
  value        = var.harbor_core_xsrf_key
  key_vault_id = azurerm_key_vault.this.id
  depends_on   = [time_sleep.rbac_propagation, time_sleep.network_acl_propagation]
}

resource "azurerm_key_vault_secret" "harbor_jobservice_secret" {
  name         = "harbor-jobservice-secret"
  value        = var.harbor_jobservice_secret
  key_vault_id = azurerm_key_vault.this.id
  depends_on   = [time_sleep.rbac_propagation, time_sleep.network_acl_propagation]
}

resource "azurerm_key_vault_secret" "harbor_registry_http_secret" {
  name         = "harbor-registry-http-secret"
  value        = var.harbor_registry_http_secret
  key_vault_id = azurerm_key_vault.this.id
  depends_on   = [time_sleep.rbac_propagation, time_sleep.network_acl_propagation]
}

resource "azurerm_key_vault_secret" "harbor_registry_passwd" {
  name         = "harbor-registry-passwd"
  value        = var.harbor_registry_passwd
  key_vault_id = azurerm_key_vault.this.id
  depends_on   = [time_sleep.rbac_propagation, time_sleep.network_acl_propagation]
}

resource "azurerm_key_vault_secret" "harbor_registry_htpasswd" {
  name         = "harbor-registry-htpasswd"
  value        = var.harbor_registry_htpasswd
  key_vault_id = azurerm_key_vault.this.id
  depends_on   = [time_sleep.rbac_propagation, time_sleep.network_acl_propagation]
}
