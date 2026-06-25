output "workspace_id" {
  description = "Log Analytics workspace resource ID."
  value       = azurerm_log_analytics_workspace.this.id
}

output "workspace_key" {
  description = "Primary shared key for the Log Analytics workspace."
  value       = azurerm_log_analytics_workspace.this.primary_shared_key
  sensitive   = true
}
