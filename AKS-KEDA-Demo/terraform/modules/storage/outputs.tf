output "storage_account_name" {
  value = azurerm_storage_account.this.name
}

output "storage_account_id" {
  value = azurerm_storage_account.this.id
}

output "storage_queue_name" {
  value = azurerm_storage_queue.this.name
}
