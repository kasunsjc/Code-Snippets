output "prometheus_workspace_id" {
  value = azapi_resource.prometheus_workspace.id
}

output "prometheus_query_endpoint" {
  value = try(azapi_resource.prometheus_workspace.output["properties"]["metrics"]["prometheusQueryEndpoint"], "")
}

output "grafana_url" {
  value = try(azapi_resource.grafana.output["properties"]["endpoint"], "")
}

output "grafana_principal_id" {
  value = local.grafana_principal_id
}

output "data_collection_rule_id" {
  value = azapi_resource.dcr.id
}
