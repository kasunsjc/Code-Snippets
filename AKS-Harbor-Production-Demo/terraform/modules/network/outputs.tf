output "vnet_id" {
  value = azurerm_virtual_network.this.id
}

output "aks_subnet_id" {
  value = azurerm_subnet.aks.id
}

output "postgres_subnet_id" {
  value = azurerm_subnet.postgres.id
}

output "privatelink_subnet_id" {
  value = azurerm_subnet.privatelink.id
}

output "bastion_subnet_id" {
  value = azurerm_subnet.bastion.id
}

output "bastion_subnet_address_prefix" {
  value = azurerm_subnet.bastion.address_prefixes[0]
}

output "jumpbox_subnet_id" {
  value = azurerm_subnet.jumpbox.id
}

output "jumpbox_subnet_address_prefix" {
  value = azurerm_subnet.jumpbox.address_prefixes[0]
}

output "postgres_private_dns_zone_id" {
  value = azurerm_private_dns_zone.postgres.id
}

output "redis_private_dns_zone_id" {
  value = azurerm_private_dns_zone.redis.id
}

output "vault_private_dns_zone_id" {
  value = azurerm_private_dns_zone.vault.id
}
