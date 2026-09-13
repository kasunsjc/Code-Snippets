output "host" {
  value = azurerm_redis_cache.this.hostname
}

output "primary_access_key" {
  value     = azurerm_redis_cache.this.primary_access_key
  sensitive = true
}

output "redis_password" {
  value     = random_password.redis.result
  sensitive = true
}
