output "host" {
  value = azurerm_managed_redis.this.hostname
}

output "port" {
  value = azurerm_managed_redis.this.default_database[0].port
}

output "redis_password" {
  value     = azurerm_managed_redis.this.default_database[0].primary_access_key
  sensitive = true
}
