output "namespace_name" {
  value = azurerm_eventhub_namespace.this.name
}

output "namespace_id" {
  value = azurerm_eventhub_namespace.this.id
}

output "eventhub_name" {
  value = azurerm_eventhub.this.name
}
