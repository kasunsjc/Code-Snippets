output "key_vault_name" {
  description = "Name of the Key Vault."
  value       = azurerm_key_vault.this.name
}

output "key_vault_id" {
  description = "Resource ID of the Key Vault."
  value       = azurerm_key_vault.this.id
}

output "certificate_versionless_secret_id" {
  description = "Versionless secret URI of the imported certificate."
  value       = azurerm_key_vault_certificate.ingress.versionless_secret_id
}
