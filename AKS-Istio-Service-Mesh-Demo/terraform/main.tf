locals {
  name_prefix         = "${var.project}-${var.environment}"
  resource_group_name = "rg-${local.name_prefix}"
  node_resource_group = "rg-${local.name_prefix}-nodes"
  cluster_name        = "aks-${local.name_prefix}"
  log_workspace_name  = "log-${local.name_prefix}"
  prometheus_ws_name  = "prom-${local.name_prefix}"
  grafana_name        = "graf-${replace(local.name_prefix, "-", "")}-${random_string.suffix.result}"

  tags = merge({
    project     = var.project
    environment = var.environment
    demo        = "aks-istio-service-mesh"
    managed_by  = "terraform"
  }, var.tags)
}

resource "random_string" "suffix" {
  length  = 5
  upper   = false
  special = false
  numeric = true
}

resource "azurerm_resource_group" "this" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.tags
}

# --- Observability (officially verified path for the Istio add-on) ------------
# Kiali/Jaeger are OSS add-ons that are NOT part of the managed Istio add-on and
# are installed separately via kubectl (see kubernetes-manifests/observability).

resource "azurerm_log_analytics_workspace" "this" {
  count               = var.enable_monitoring ? 1 : 0
  name                = local.log_workspace_name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = local.tags
}

resource "azurerm_monitor_workspace" "this" {
  count               = var.enable_monitoring ? 1 : 0
  name                = local.prometheus_ws_name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.tags
}

resource "azurerm_dashboard_grafana" "this" {
  count                         = var.enable_monitoring ? 1 : 0
  name                          = local.grafana_name
  location                      = azurerm_resource_group.this.location
  resource_group_name           = azurerm_resource_group.this.name
  grafana_major_version         = "11"
  api_key_enabled               = true
  public_network_access_enabled = true
  zone_redundancy_enabled       = false
  identity {
    type = "SystemAssigned"
  }

  azure_monitor_workspace_integrations {
    resource_id = azurerm_monitor_workspace.this[0].id
  }

  tags = local.tags
}

resource "azurerm_role_assignment" "grafana_monitoring_reader" {
  count                = var.enable_monitoring ? 1 : 0
  scope                = azurerm_monitor_workspace.this[0].id
  role_definition_name = "Monitoring Data Reader"
  principal_id         = azurerm_dashboard_grafana.this[0].identity[0].principal_id
}

# --- AKS cluster with the Istio-based service mesh add-on ----------------------

resource "azurerm_kubernetes_cluster" "this" {
  name                = local.cluster_name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  dns_prefix          = replace(local.name_prefix, "-", "")
  kubernetes_version  = var.kubernetes_version
  node_resource_group = local.node_resource_group
  sku_tier            = "Standard"

  default_node_pool {
    name                         = "system"
    vm_size                      = var.node_vm_size
    node_count                   = var.node_count
    only_critical_addons_enabled = false
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_policy      = "azure"
    load_balancer_sku   = "standard"
  }

  # The Istio add-on itself: istiod control plane + optional ingress gateways.
  # `revisions` is left to the caller - AKS assigns its current default
  # supported revision when the list is empty and reports it back after apply.
  service_mesh_profile {
    mode                             = "Istio"
    revisions                        = var.istio_revisions
    internal_ingress_gateway_enabled = var.internal_ingress_gateway_enabled
    external_ingress_gateway_enabled = var.external_ingress_gateway_enabled
  }

  dynamic "oms_agent" {
    for_each = var.enable_monitoring ? [1] : []
    content {
      log_analytics_workspace_id = azurerm_log_analytics_workspace.this[0].id
    }
  }

  dynamic "monitor_metrics" {
    for_each = var.enable_monitoring ? [1] : []
    content {
      annotations_allowed = null
      labels_allowed      = null
    }
  }

  tags = local.tags
}

# Managed Prometheus needs a Data Collection Endpoint/Rule wired to the cluster;
# `monitor_metrics` on the cluster auto-creates and associates these when a
# Prometheus (Monitor) workspace is discoverable in the same resource group, but
# we still need to point the cluster's rule association at our workspace.
resource "azurerm_monitor_data_collection_endpoint" "this" {
  count               = var.enable_monitoring ? 1 : 0
  name                = "dce-${local.name_prefix}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.tags
}

resource "azurerm_monitor_data_collection_rule" "this" {
  count                       = var.enable_monitoring ? 1 : 0
  name                        = "dcr-${local.name_prefix}"
  location                    = azurerm_resource_group.this.location
  resource_group_name         = azurerm_resource_group.this.name
  data_collection_endpoint_id = azurerm_monitor_data_collection_endpoint.this[0].id
  kind                        = "Linux"

  destinations {
    monitor_account {
      monitor_account_id = azurerm_monitor_workspace.this[0].id
      name               = "prometheus-destination"
    }
  }

  data_flow {
    streams      = ["Microsoft-PrometheusMetrics"]
    destinations = ["prometheus-destination"]
  }

  data_sources {
    prometheus_forwarder {
      streams = ["Microsoft-PrometheusMetrics"]
      name    = "prometheus-source"
    }
  }

  tags = local.tags
}

resource "azurerm_monitor_data_collection_rule_association" "this" {
  count                   = var.enable_monitoring ? 1 : 0
  name                    = "dcra-${local.name_prefix}"
  target_resource_id      = azurerm_kubernetes_cluster.this.id
  data_collection_rule_id = azurerm_monitor_data_collection_rule.this[0].id
}
