resource "azurerm_postgresql_flexible_server" "this" {
  name                          = "psql-${var.project}-${var.environment}"
  resource_group_name           = var.resource_group_name
  location                      = var.location
  version                       = "16"
  delegated_subnet_id           = var.subnet_id
  private_dns_zone_id           = var.private_dns_zone_id
  public_network_access_enabled = false
  zone                          = "1"
  sku_name                      = "GP_Standard_D2s_v3"
  storage_mb                    = 65536

  backup_retention_days        = 35
  geo_redundant_backup_enabled = true
  high_availability {
    mode                      = "ZoneRedundant"
    standby_availability_zone = "2"
  }

  administrator_login    = "harboradmin"
  administrator_password = random_password.postgres.result

  authentication {
    active_directory_auth_enabled = true
    password_auth_enabled         = true
  }

  tags = var.tags

  lifecycle {
    ignore_changes = [zone, high_availability[0].standby_availability_zone]
  }
}

resource "azurerm_postgresql_flexible_server_database" "registry" {
  name      = "registry"
  server_id = azurerm_postgresql_flexible_server.this.id
  charset   = "UTF8"
  collation = "en_US.utf8"
}

resource "azurerm_postgresql_flexible_server_active_directory_administrator" "this" {
  count = var.user_object_id == "" ? 0 : 1

  server_name         = azurerm_postgresql_flexible_server.this.name
  resource_group_name = var.resource_group_name
  tenant_id           = var.tenant_id
  object_id           = var.user_object_id
  principal_name      = "Harbor Admin"
  principal_type      = "User"
}

resource "random_password" "postgres" {
  length  = 24
  special = true
}
