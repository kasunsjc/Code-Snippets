output "aks_cluster_name" {
  value = module.aks.cluster_name
}

output "aks_cluster_id" {
  value = module.aks.cluster_id
}

output "node_resource_group" {
  value = local.node_resource_group_name
}

output "oidc_issuer_url" {
  value = module.aks.oidc_issuer_url
}

output "storage_account_name" {
  value = module.storage.storage_account_name
}

output "storage_queue_name" {
  value = module.storage.storage_queue_name
}

output "checkpoint_container_name" {
  value = module.storage.checkpoint_container_name
}

output "storage_connection_string" {
  description = "Storage account connection string."
  value       = module.storage.primary_connection_string
  sensitive   = true
}

output "eventhub_namespace_name" {
  value = module.eventhub.namespace_name
}

output "eventhub_name" {
  value = module.eventhub.eventhub_name
}

output "eventhub_namespace_connection_string" {
  description = "Event Hub namespace connection string."
  value       = module.eventhub.namespace_primary_connection_string
  sensitive   = true
}

output "sample_apps_env" {
  description = "WARNING: Demo-only output. Exposes sample app environment values including connection strings in plaintext. Not recommended for production."
  value = {
    AZURE_STORAGE_CONNECTION_STRING            = nonsensitive(module.storage.primary_connection_string)
    QUEUE_NAME                                 = module.storage.storage_queue_name
    AZURE_EVENTHUB_CONNECTION_STRING           = nonsensitive(module.eventhub.namespace_primary_connection_string)
    EVENTHUB_NAME                              = module.eventhub.eventhub_name
    CONSUMER_GROUP                             = "$Default"
    STARTING_POSITION                          = "@latest"
    AZURE_STORAGE_CHECKPOINT_CONNECTION_STRING = nonsensitive(module.storage.primary_connection_string)
    CHECKPOINT_CONTAINER_NAME                  = module.storage.checkpoint_container_name
  }
}

output "prometheus_query_endpoint" {
  value = module.monitoring.prometheus_query_endpoint
}

output "prometheus_workload_identity_client_id" {
  description = "Client ID of the managed identity used by the KEDA Prometheus scaler."
  value       = module.prometheus_workload_identity.client_id
}

output "grafana_url" {
  value = module.monitoring.grafana_url
}

output "acr_name" {
  value = module.acr.name
}

output "acr_login_server" {
  value = module.acr.login_server
}
