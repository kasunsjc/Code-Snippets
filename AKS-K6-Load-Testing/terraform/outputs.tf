output "subscription_id" {
  description = "Subscription containing the demo, used by deploy and cleanup scripts."
  value       = var.subscription_id
}

output "resource_group_name" {
  description = "Resource group containing the AKS cluster."
  value       = azurerm_resource_group.demo.name
}

output "cluster_name" {
  description = "AKS cluster name used to retrieve kubeconfig."
  value       = azurerm_kubernetes_cluster.demo.name
}

output "node_resource_group_name" {
  description = "AKS-managed resource group containing nodes, networking, and service public IPs."
  value       = azurerm_kubernetes_cluster.demo.node_resource_group
}

output "cluster_id" {
  description = "Azure resource ID of the AKS cluster."
  value       = azurerm_kubernetes_cluster.demo.id
}

output "httpbin_fqdn" {
  description = "Public hostname for httpbin."
  value       = "${var.httpbin_subdomain}.${var.dns_zone_name}"
}

output "ingress_public_ip" {
  description = "Static IPv4 address assigned to Traefik."
  value       = azurerm_public_ip.ingress.ip_address
}

output "ingress_public_ip_name" {
  description = "Public IP resource name used by the AKS LoadBalancer annotation."
  value       = azurerm_public_ip.ingress.name
}

output "dns_zone_name" {
  description = "Existing Azure DNS zone."
  value       = data.azurerm_dns_zone.existing.name
}

output "dns_zone_resource_group" {
  description = "Existing DNS zone resource group, retained during cleanup."
  value       = var.dns_zone_resource_group
}

output "dns_record_name" {
  description = "DNS A record owned by this demo and removed by Terraform destroy."
  value       = azurerm_dns_a_record.httpbin.name
}

output "acme_email" {
  description = "ACME contact email."
  value       = var.acme_email
}

output "cert_manager_client_id" {
  description = "Workload identity client ID for cert-manager."
  value       = azurerm_user_assigned_identity.cert_manager.client_id
}

output "grafana_name" {
  description = "Azure Managed Grafana resource name."
  value       = azurerm_dashboard_grafana.demo.name
}

output "grafana_endpoint" {
  description = "Azure Managed Grafana browser endpoint."
  value       = azurerm_dashboard_grafana.demo.endpoint
}

output "prometheus_query_endpoint" {
  description = "Managed Prometheus query endpoint for Grafana."
  value       = azurerm_monitor_workspace.prometheus.query_endpoint
}

output "k6_metrics_client_id" {
  description = "Workload identity client ID used by the k6 metrics relay."
  value       = azurerm_user_assigned_identity.k6_metrics.client_id
}

output "tenant_id" {
  description = "Entra tenant used for workload identity authentication."
  value       = data.azurerm_client_config.current.tenant_id
}

output "prometheus_remote_write_endpoint" {
  description = "Authenticated Azure remote-write endpoint for the demo's DCR."
  value       = "${azurerm_monitor_data_collection_endpoint.prometheus.metrics_ingestion_endpoint}/dataCollectionRules/${azurerm_monitor_data_collection_rule.prometheus.immutable_id}/streams/Microsoft-PrometheusMetrics/api/v1/write?api-version=2023-04-24"
}