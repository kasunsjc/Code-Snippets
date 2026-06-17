output "namespace_name" {
  value = azurerm_eventhub_namespace.this.name
}

output "namespace_id" {
  value = azurerm_eventhub_namespace.this.id
}

output "eventhub_name" {
  value = azurerm_eventhub.this.name
}

output "namespace_primary_connection_string" {
  value     = azurerm_eventhub_namespace.this.default_primary_connection_string
  sensitive = true
}
