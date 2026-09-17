# Classic Azure Cache for Redis (azurerm_redis_cache) is retired for new
# resources; azurerm_managed_redis is the Microsoft.Cache/RedisEnterprise
# based replacement.
resource "azurerm_managed_redis" "this" {
  name                  = "redis-${var.project}-${var.environment}"
  location              = var.location
  resource_group_name   = var.resource_group_name
  sku_name              = "Balanced_B1"
  public_network_access = "Disabled"
  tags                  = var.tags

  default_database {
    access_keys_authentication_enabled = true
    client_protocol                    = "Encrypted"
    clustering_policy                  = "OSSCluster"
    eviction_policy                    = "NoEviction"
  }
}

resource "azurerm_private_endpoint" "redis" {
  name                = "pe-redis-${var.project}-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.privatelink_subnet_id

  private_service_connection {
    name                           = "redis-psc"
    private_connection_resource_id = azurerm_managed_redis.this.id
    is_manual_connection           = false
    subresource_names              = ["redisEnterprise"]
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [var.private_dns_zone_id]
  }
}
