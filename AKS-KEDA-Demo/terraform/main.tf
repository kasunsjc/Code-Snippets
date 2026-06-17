data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "this" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

resource "random_string" "suffix" {
  length  = 6
  lower   = true
  upper   = false
  numeric = true
  special = false
}

locals {
  node_resource_group_name = "rg-${var.cluster_name}-nodes"

  storage_account_name = substr(replace(lower("st${var.cluster_name}keda"), "-", ""), 0, 24)
  eventhub_namespace   = substr(replace(lower("eh${var.cluster_name}${random_string.suffix.result}"), "-", ""), 0, 50)

  generated_acr_name = substr(
    replace(lower("acr${var.cluster_name}${random_string.suffix.result}"), "-", ""),
    0,
    50
  )
  effective_acr_name = var.acr_name == "" ? local.generated_acr_name : var.acr_name
}

module "log_analytics" {
  source = "./modules/log_analytics"

  workspace_name      = "${var.cluster_name}-law"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = var.tags
}

module "monitoring" {
  source = "./modules/monitoring"

  base_name         = var.cluster_name
  location          = var.location
  resource_group_id = azurerm_resource_group.this.id
  user_object_id    = var.user_object_id
  tags              = var.tags
}

module "aks" {
  source = "./modules/aks"

  cluster_name               = var.cluster_name
  location                   = var.location
  resource_group_name        = azurerm_resource_group.this.name
  kubernetes_version         = var.kubernetes_version
  node_count                 = var.node_count
  enable_node_autoscaling    = var.enable_node_autoscaling
  node_min_count             = var.node_min_count
  node_max_count             = var.node_max_count
  node_vm_size               = var.node_vm_size
  node_resource_group_name   = local.node_resource_group_name
  log_analytics_workspace_id = module.log_analytics.workspace_id
  user_object_id             = var.user_object_id
  tags                       = var.tags
}

module "storage" {
  source = "./modules/storage"

  storage_account_name      = local.storage_account_name
  resource_group_name       = azurerm_resource_group.this.name
  location                  = var.location
  checkpoint_container_name = var.checkpoint_container_name
  tags                      = var.tags
}

module "eventhub" {
  source = "./modules/eventhub"

  namespace_name      = local.eventhub_namespace
  resource_group_name = azurerm_resource_group.this.name
  location            = var.location
  eventhub_name       = "keda-demo-hub"
  tags                = var.tags
}

module "acr" {
  source = "./modules/acr"

  name                = local.effective_acr_name
  resource_group_name = azurerm_resource_group.this.name
  location            = var.location
  sku                 = var.acr_sku
  tags                = var.tags
}

# Workload identity for the KEDA Prometheus scaler.
# Allows KEDA to query Azure Managed Prometheus without a static bearer token.
module "prometheus_workload_identity" {
  source = "./modules/workload_identity"

  name                    = "${var.cluster_name}-keda-prometheus"
  resource_group_name     = azurerm_resource_group.this.name
  location                = var.location
  oidc_issuer_url         = module.aks.oidc_issuer_url
  prometheus_workspace_id = module.monitoring.prometheus_workspace_id
  tags                    = var.tags
}

resource "azurerm_role_assignment" "acr_pull" {
  scope                = module.acr.id
  role_definition_name = "AcrPull"
  principal_id         = module.aks.kubelet_identity_object_id
}

resource "azapi_resource" "dcr_association" {
  type      = "Microsoft.Insights/dataCollectionRuleAssociations@2022-06-01"
  name      = "MSProm-${var.cluster_name}"
  parent_id = module.aks.cluster_id

  body = {
    properties = {
      dataCollectionRuleId = module.monitoring.data_collection_rule_id
      description          = "Association of Data Collection Rule for Azure Managed Prometheus"
    }
  }
}

resource "azapi_resource" "node_recording_rules" {
  type                      = "Microsoft.AlertsManagement/prometheusRuleGroups@2023-03-01"
  name                      = "NodeRecordingRulesRuleGroup-${var.cluster_name}"
  parent_id                 = azurerm_resource_group.this.id
  location                  = var.location
  schema_validation_enabled = false

  body = {
    properties = {
      description = "Prometheus recording rules for node metrics"
      scopes = [
        module.monitoring.prometheus_workspace_id,
        module.aks.cluster_id
      ]
      enabled     = true
      clusterName = var.cluster_name
      interval    = "PT1M"
      rules = [
        { record = "instance:node_num_cpu:sum", expression = "count without (cpu, mode) (node_cpu_seconds_total{job=\"node\",mode=\"idle\"})" },
        { record = "instance:node_cpu_utilisation:rate5m", expression = "1 - avg without (cpu) (sum without (mode) (rate(node_cpu_seconds_total{job=\"node\", mode=~\"idle|iowait|steal\"}[5m])))" },
        { record = "instance:node_load1_per_cpu:ratio", expression = "(node_load1{job=\"node\"} / instance:node_num_cpu:sum{job=\"node\"})" },
        { record = "instance:node_memory_utilisation:ratio", expression = "1 - ((node_memory_MemAvailable_bytes{job=\"node\"} or (node_memory_Buffers_bytes{job=\"node\"} + node_memory_Cached_bytes{job=\"node\"} + node_memory_MemFree_bytes{job=\"node\"} + node_memory_Slab_bytes{job=\"node\"})) / node_memory_MemTotal_bytes{job=\"node\"})" },
        { record = "instance:node_vmstat_pgmajfault:rate5m", expression = "rate(node_vmstat_pgmajfault{job=\"node\"}[5m])" },
        { record = "instance_device:node_disk_io_time_seconds:rate5m", expression = "rate(node_disk_io_time_seconds_total{job=\"node\", device!=\"\"}[5m])" },
        { record = "instance_device:node_disk_io_time_weighted_seconds:rate5m", expression = "rate(node_disk_io_time_weighted_seconds_total{job=\"node\", device!=\"\"}[5m])" },
        { record = "instance:node_network_receive_bytes_excluding_lo:rate5m", expression = "sum without (device) (rate(node_network_receive_bytes_total{job=\"node\", device!=\"lo\"}[5m]))" },
        { record = "instance:node_network_transmit_bytes_excluding_lo:rate5m", expression = "sum without (device) (rate(node_network_transmit_bytes_total{job=\"node\", device!=\"lo\"}[5m]))" },
        { record = "instance:node_network_receive_drop_excluding_lo:rate5m", expression = "sum without (device) (rate(node_network_receive_drop_total{job=\"node\", device!=\"lo\"}[5m]))" },
        { record = "instance:node_network_transmit_drop_excluding_lo:rate5m", expression = "sum without (device) (rate(node_network_transmit_drop_total{job=\"node\", device!=\"lo\"}[5m]))" }
      ]
    }
  }
}

resource "azapi_resource" "kubernetes_recording_rules" {
  type                      = "Microsoft.AlertsManagement/prometheusRuleGroups@2023-03-01"
  name                      = "KubernetesRecordingRulesRuleGroup-${var.cluster_name}"
  parent_id                 = azurerm_resource_group.this.id
  location                  = var.location
  schema_validation_enabled = false

  body = {
    properties = {
      description = "Prometheus recording rules for Kubernetes resources"
      scopes = [
        module.monitoring.prometheus_workspace_id,
        module.aks.cluster_id
      ]
      enabled     = true
      clusterName = var.cluster_name
      interval    = "PT1M"
      rules = [
        { record = "node_namespace_pod_container:container_cpu_usage_seconds_total:sum_irate", expression = "sum by (cluster, namespace, pod, container) (irate(container_cpu_usage_seconds_total{job=\"cadvisor\", image!=\"\"}[5m])) * on (cluster, namespace, pod) group_left(node) topk by (cluster, namespace, pod) (1, max by(cluster, namespace, pod, node) (kube_pod_info{node!=\"\"}))" },
        { record = "node_namespace_pod_container:container_memory_working_set_bytes", expression = "container_memory_working_set_bytes{job=\"cadvisor\", image!=\"\"} * on (namespace, pod) group_left(node) topk by(namespace, pod) (1, max by(namespace, pod, node) (kube_pod_info{node!=\"\"}))" },
        { record = "node_namespace_pod_container:container_memory_rss", expression = "container_memory_rss{job=\"cadvisor\", image!=\"\"} * on (namespace, pod) group_left(node) topk by(namespace, pod) (1, max by(namespace, pod, node) (kube_pod_info{node!=\"\"}))" },
        { record = "node_namespace_pod_container:container_memory_cache", expression = "container_memory_cache{job=\"cadvisor\", image!=\"\"} * on (namespace, pod) group_left(node) topk by(namespace, pod) (1, max by(namespace, pod, node) (kube_pod_info{node!=\"\"}))" },
        { record = "node_namespace_pod_container:container_memory_swap", expression = "container_memory_swap{job=\"cadvisor\", image!=\"\"} * on (namespace, pod) group_left(node) topk by(namespace, pod) (1, max by(namespace, pod, node) (kube_pod_info{node!=\"\"}))" },
        { record = "cluster:namespace:pod_memory:active:kube_pod_container_resource_requests", expression = "kube_pod_container_resource_requests{resource=\"memory\",job=\"kube-state-metrics\"} * on (namespace, pod, cluster) group_left() max by (namespace, pod, cluster) ((kube_pod_status_phase{phase=~\"Pending|Running\"} == 1))" },
        { record = "namespace_memory:kube_pod_container_resource_requests:sum", expression = "sum by (namespace, cluster) (sum by (namespace, pod, cluster) (max by (namespace, pod, container, cluster) (kube_pod_container_resource_requests{resource=\"memory\",job=\"kube-state-metrics\"}) * on(namespace, pod, cluster) group_left() max by (namespace, pod, cluster) (kube_pod_status_phase{phase=~\"Pending|Running\"} == 1)))" },
        { record = "cluster:namespace:pod_cpu:active:kube_pod_container_resource_requests", expression = "kube_pod_container_resource_requests{resource=\"cpu\",job=\"kube-state-metrics\"} * on (namespace, pod, cluster) group_left() max by (namespace, pod, cluster) ((kube_pod_status_phase{phase=~\"Pending|Running\"} == 1))" },
        { record = "namespace_cpu:kube_pod_container_resource_requests:sum", expression = "sum by (namespace, cluster) (sum by (namespace, pod, cluster) (max by (namespace, pod, container, cluster) (kube_pod_container_resource_requests{resource=\"cpu\",job=\"kube-state-metrics\"}) * on(namespace, pod, cluster) group_left() max by (namespace, pod, cluster) (kube_pod_status_phase{phase=~\"Pending|Running\"} == 1)))" },
        { record = ":node_memory_MemAvailable_bytes:sum", expression = "sum(node_memory_MemAvailable_bytes{job=\"node\"} or (node_memory_Buffers_bytes{job=\"node\"} + node_memory_Cached_bytes{job=\"node\"} + node_memory_MemFree_bytes{job=\"node\"} + node_memory_Slab_bytes{job=\"node\"})) by (cluster)" },
        { record = "cluster:node_cpu:ratio_rate5m", expression = "sum(rate(node_cpu_seconds_total{job=\"node\",mode!=\"idle\",mode!=\"iowait\",mode!=\"steal\"}[5m])) by (cluster) / count(sum(node_cpu_seconds_total{job=\"node\"}) by (cluster, instance, cpu)) by (cluster)" }
      ]
    }
  }
}

resource "azapi_resource" "ux_recording_rules" {
  type                      = "Microsoft.AlertsManagement/prometheusRuleGroups@2023-03-01"
  name                      = "UXRecordingRulesRuleGroup-${var.cluster_name}"
  parent_id                 = azurerm_resource_group.this.id
  location                  = var.location
  schema_validation_enabled = false

  body = {
    properties = {
      description = "UX recording rules for AKS monitoring dashboards"
      scopes = [
        module.monitoring.prometheus_workspace_id,
        module.aks.cluster_id
      ]
      enabled     = true
      clusterName = var.cluster_name
      interval    = "PT1M"
      rules = [
        {
          record     = "ux:pod_cpu_usage:sum_irate"
          expression = "(sum by (namespace, pod, cluster, microsoft_resourceid) ( irate(container_cpu_usage_seconds_total{container != \"\", pod != \"\", job = \"cadvisor\"}[5m]) )) * on (pod, namespace, cluster, microsoft_resourceid) group_left (node, created_by_name, created_by_kind) (max by (node, created_by_name, created_by_kind, pod, namespace, cluster, microsoft_resourceid) (kube_pod_info{pod != \"\", job = \"kube-state-metrics\"}))"
        },
        {
          record     = "ux:controller_cpu_usage:sum_irate"
          expression = "sum by (namespace, node, cluster, created_by_name, created_by_kind, microsoft_resourceid) ( ux:pod_cpu_usage:sum_irate )"
        },
        {
          record     = "ux:pod_workingset_memory:sum"
          expression = "( sum by (namespace, pod, cluster, microsoft_resourceid) ( container_memory_working_set_bytes{container != \"\", pod != \"\", job = \"cadvisor\"} ) ) * on (pod, namespace, cluster, microsoft_resourceid) group_left (node, created_by_name, created_by_kind) (max by (node, created_by_name, created_by_kind, pod, namespace, cluster, microsoft_resourceid) (kube_pod_info{pod != \"\", job = \"kube-state-metrics\"}))"
        },
        {
          record     = "ux:controller_workingset_memory:sum"
          expression = "sum by (namespace, node, cluster, created_by_name, created_by_kind, microsoft_resourceid) ( ux:pod_workingset_memory:sum )"
        },
        {
          record     = "ux:pod_rss_memory:sum"
          expression = "( sum by (namespace, pod, cluster, microsoft_resourceid) ( container_memory_rss{container != \"\", pod != \"\", job = \"cadvisor\"} ) ) * on (pod, namespace, cluster, microsoft_resourceid) group_left (node, created_by_name, created_by_kind) (max by (node, created_by_name, created_by_kind, pod, namespace, cluster, microsoft_resourceid) (kube_pod_info{pod != \"\", job = \"kube-state-metrics\"}))"
        },
        {
          record     = "ux:controller_rss_memory:sum"
          expression = "sum by (namespace, node, cluster, created_by_name, created_by_kind, microsoft_resourceid) ( ux:pod_rss_memory:sum )"
        },
        {
          record     = "ux:pod_container_count:sum"
          expression = "sum by (node, created_by_name, created_by_kind, namespace, cluster, pod, microsoft_resourceid) ( ( ( sum by (container, pod, namespace, cluster, microsoft_resourceid) (kube_pod_container_info{container != \"\", pod != \"\", container_id != \"\", job = \"kube-state-metrics\"}) or sum by (container, pod, namespace, cluster, microsoft_resourceid) (kube_pod_init_container_info{container != \"\", pod != \"\", container_id != \"\", job = \"kube-state-metrics\"}) ) * on (pod, namespace, cluster, microsoft_resourceid) group_left (node, created_by_name, created_by_kind) ( max by (node, created_by_name, created_by_kind, pod, namespace, cluster, microsoft_resourceid) ( kube_pod_info{pod != \"\", job = \"kube-state-metrics\"} ) ) ) )"
        },
        {
          record     = "ux:controller_container_count:sum"
          expression = "sum by (node, created_by_name, created_by_kind, namespace, cluster, microsoft_resourceid) ( ux:pod_container_count:sum )"
        },
        {
          record     = "ux:pod_container_restarts:max"
          expression = "max by (node, created_by_name, created_by_kind, namespace, cluster, pod, microsoft_resourceid) ( ( ( max by (container, pod, namespace, cluster, microsoft_resourceid) (kube_pod_container_status_restarts_total{container != \"\", pod != \"\", job = \"kube-state-metrics\"}) or sum by (container, pod, namespace, cluster, microsoft_resourceid) (kube_pod_init_status_restarts_total{container != \"\", pod != \"\", job = \"kube-state-metrics\"}) ) * on (pod, namespace, cluster, microsoft_resourceid) group_left (node, created_by_name, created_by_kind) ( max by (node, created_by_name, created_by_kind, pod, namespace, cluster, microsoft_resourceid) ( kube_pod_info{pod != \"\", job = \"kube-state-metrics\"} ) ) ) )"
        },
        {
          record     = "ux:controller_container_restarts:max"
          expression = "max by (node, created_by_name, created_by_kind, namespace, cluster, microsoft_resourceid) ( ux:pod_container_restarts:max )"
        },
        {
          record     = "ux:pod_resource_limit:sum"
          expression = "(sum by (cluster, pod, namespace, resource, microsoft_resourceid) ( ( max by (cluster, microsoft_resourceid, pod, container, namespace, resource) (kube_pod_container_resource_limits{container != \"\", pod != \"\", job = \"kube-state-metrics\"}) ) ) unless (count by (pod, namespace, cluster, resource, microsoft_resourceid) (kube_pod_container_resource_limits{container != \"\", pod != \"\", job = \"kube-state-metrics\"}) != on (pod, namespace, cluster, microsoft_resourceid) group_left() sum by (pod, namespace, cluster, microsoft_resourceid) (kube_pod_container_info{container != \"\", pod != \"\", job = \"kube-state-metrics\"}) )) * on (namespace, pod, cluster, microsoft_resourceid) group_left (node, created_by_kind, created_by_name) ( kube_pod_info{pod != \"\", job = \"kube-state-metrics\"} )"
        },
        {
          record     = "ux:controller_resource_limit:sum"
          expression = "sum by (cluster, namespace, created_by_name, created_by_kind, node, resource, microsoft_resourceid) ( ux:pod_resource_limit:sum )"
        },
        {
          record     = "ux:controller_pod_phase_count:sum"
          expression = "sum by (cluster, phase, node, created_by_kind, created_by_name, namespace, microsoft_resourceid) ( ( (kube_pod_status_phase{job=\"kube-state-metrics\",pod!=\"\"}) or (label_replace((count(kube_pod_deletion_timestamp{job=\"kube-state-metrics\",pod!=\"\"}) by (namespace, pod, cluster, microsoft_resourceid) * count(kube_pod_status_reason{reason=\"NodeLost\", job=\"kube-state-metrics\"} == 0) by (namespace, pod, cluster, microsoft_resourceid)), \"phase\", \"terminating\", \"\", \"\"))) * on (pod, namespace, cluster, microsoft_resourceid) group_left (node, created_by_name, created_by_kind) ( max by (node, created_by_name, created_by_kind, pod, namespace, cluster, microsoft_resourceid) ( kube_pod_info{job=\"kube-state-metrics\",pod!=\"\"} ) ) )"
        },
        {
          record     = "ux:cluster_pod_phase_count:sum"
          expression = "sum by (cluster, phase, node, namespace, microsoft_resourceid) ( ux:controller_pod_phase_count:sum )"
        },
        {
          record     = "ux:node_cpu_usage:sum_irate"
          expression = "sum by (instance, cluster, microsoft_resourceid) ( (1 - irate(node_cpu_seconds_total{job=\"node\", mode=\"idle\"}[5m])) )"
        },
        {
          record     = "ux:node_memory_usage:sum"
          expression = "sum by (instance, cluster, microsoft_resourceid) (( node_memory_MemTotal_bytes{job = \"node\"} - node_memory_MemFree_bytes{job = \"node\"} - node_memory_cached_bytes{job = \"node\"} - node_memory_buffers_bytes{job = \"node\"} ))"
        },
        {
          record     = "ux:node_network_receive_drop_total:sum_irate"
          expression = "sum by (instance, cluster, microsoft_resourceid) (irate(node_network_receive_drop_total{job=\"node\", device!=\"lo\"}[5m]))"
        },
        {
          record     = "ux:node_network_transmit_drop_total:sum_irate"
          expression = "sum by (instance, cluster, microsoft_resourceid) (irate(node_network_transmit_drop_total{job=\"node\", device!=\"lo\"}[5m]))"
        }
      ]
    }
  }
}
