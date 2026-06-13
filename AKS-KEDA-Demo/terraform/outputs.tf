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

output "eventhub_namespace_name" {
  value = module.eventhub.namespace_name
}

output "eventhub_name" {
  value = module.eventhub.eventhub_name
}

output "prometheus_query_endpoint" {
  value = module.monitoring.prometheus_query_endpoint
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
