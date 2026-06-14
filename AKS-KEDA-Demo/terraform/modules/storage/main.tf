resource "azurerm_storage_account" "this" {
  name                            = var.storage_account_name
  resource_group_name             = var.resource_group_name
  location                        = var.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  account_kind                    = "StorageV2"
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  tags                            = var.tags
}

resource "time_sleep" "wait_for_storage_dns" {
  depends_on = [azurerm_storage_account.this]

  # Newly created Storage endpoints can take a short time to propagate in DNS.
  # This prevents intermittent queue create failures: "no such host".
  create_duration = "45s"
}

resource "azurerm_storage_queue" "this" {
  name                 = var.queue_name
  storage_account_name = azurerm_storage_account.this.name
  depends_on           = [time_sleep.wait_for_storage_dns]
}
