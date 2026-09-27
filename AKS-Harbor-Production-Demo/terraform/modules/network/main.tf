resource "azurerm_virtual_network" "this" {
  name                = "vnet-${var.project}-${var.environment}"
  address_space       = ["10.50.0.0/16"]
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_subnet" "aks" {
  name                 = "snet-aks"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = ["10.50.0.0/20"]
}

resource "azurerm_subnet" "postgres" {
  name                 = "snet-postgres"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = ["10.50.16.0/24"]

  delegation {
    name = "postgres-delegation"
    service_delegation {
      name = "Microsoft.DBforPostgreSQL/flexibleServers"
    }
  }
}

resource "azurerm_subnet" "privatelink" {
  name                              = "snet-privatelink"
  resource_group_name               = var.resource_group_name
  virtual_network_name              = azurerm_virtual_network.this.name
  address_prefixes                  = ["10.50.17.0/24"]
  private_endpoint_network_policies = "Disabled"
}

resource "azurerm_private_dns_zone" "postgres" {
  name                = "privatelink.postgres.database.azure.com"
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone" "redis" {
  # Azure Managed Redis (Microsoft.Cache/RedisEnterprise) uses this zone name,
  # not privatelink.redis.cache.windows.net (that's classic Azure Cache for Redis).
  name                = "privatelink.redis.azure.net"
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone" "vault" {
  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "postgres" {
  name                  = "pdz-vnet-link-postgres"
  private_dns_zone_name = azurerm_private_dns_zone.postgres.name
  virtual_network_id    = azurerm_virtual_network.this.id
  resource_group_name   = var.resource_group_name
}

resource "azurerm_private_dns_zone_virtual_network_link" "redis" {
  name                  = "pdz-vnet-link-redis"
  private_dns_zone_name = azurerm_private_dns_zone.redis.name
  virtual_network_id    = azurerm_virtual_network.this.id
  resource_group_name   = var.resource_group_name
}

resource "azurerm_private_dns_zone_virtual_network_link" "vault" {
  name                  = "pdz-vnet-link-vault"
  private_dns_zone_name = azurerm_private_dns_zone.vault.name
  virtual_network_id    = azurerm_virtual_network.this.id
  resource_group_name   = var.resource_group_name
}
