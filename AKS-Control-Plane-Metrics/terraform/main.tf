# ============================================================
# AKS Control Plane Metrics demo
# ------------------------------------------------------------
# - AKS cluster with Azure Monitor managed Prometheus
# - Azure Monitor workspace + DCE + DCR + DCR association
# - Control plane metrics (kube-apiserver, etcd, scheduler, ...)
# - Azure Managed Grafana linked to the Azure Monitor workspace
# ============================================================

resource "random_string" "suffix" {
  length  = 4
  upper   = false
  special = false
}

locals {
  name_prefix = "${var.project}-${var.environment}"

  resource_group_name      = "rg-${local.name_prefix}"
  node_resource_group_name = "rg-${local.name_prefix}-nodes"
  cluster_name             = "aks-${local.name_prefix}"
  grafana_name             = substr("amg-${var.project}-${random_string.suffix.result}", 0, 23)

  tags = merge({
    project     = var.project
    environment = var.environment
    demo        = "aks-control-plane-metrics"
    managed_by  = "terraform"
  }, var.tags)
}

resource "azurerm_resource_group" "this" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.tags
}

# ------------------------------------------------------------
# Azure Monitor workspace (managed Prometheus metrics store)
# ------------------------------------------------------------
resource "azurerm_monitor_workspace" "this" {
  name                = "amw-${local.name_prefix}"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  tags                = local.tags
}

# ------------------------------------------------------------
# AKS cluster with the managed Prometheus add-on (ama-metrics)
# ------------------------------------------------------------
resource "azurerm_kubernetes_cluster" "this" {
  name                = local.cluster_name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  dns_prefix          = local.cluster_name
  kubernetes_version  = var.kubernetes_version
  node_resource_group = local.node_resource_group_name
  tags                = local.tags

  default_node_pool {
    name       = "system"
    vm_size    = var.node_vm_size
    node_count = var.node_count

    upgrade_settings {
      max_surge = "10%"
    }
  }

  # Control plane metrics require a managed identity.
  identity {
    type = "SystemAssigned"
  }

  # Enables the Azure Monitor managed Prometheus add-on.
  monitor_metrics {}

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
  }
}

# ------------------------------------------------------------
# Managed Prometheus data collection (DCE + DCR + association)
# ------------------------------------------------------------
resource "azurerm_monitor_data_collection_endpoint" "prometheus" {
  name                = "dce-${local.name_prefix}"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  kind                = "Linux"
  tags                = local.tags
}

resource "azurerm_monitor_data_collection_rule" "prometheus" {
  name                        = "dcr-${local.name_prefix}"
  resource_group_name         = azurerm_resource_group.this.name
  location                    = azurerm_resource_group.this.location
  data_collection_endpoint_id = azurerm_monitor_data_collection_endpoint.prometheus.id
  kind                        = "Linux"
  tags                        = local.tags

  data_sources {
    prometheus_forwarder {
      name    = "PrometheusDataSource"
      streams = ["Microsoft-PrometheusMetrics"]
    }
  }

  destinations {
    monitor_account {
      name               = "MonitoringAccount1"
      monitor_account_id = azurerm_monitor_workspace.this.id
    }
  }

  data_flow {
    streams      = ["Microsoft-PrometheusMetrics"]
    destinations = ["MonitoringAccount1"]
  }
}

resource "azurerm_monitor_data_collection_rule_association" "prometheus" {
  name                    = "dcra-${local.name_prefix}"
  target_resource_id      = azurerm_kubernetes_cluster.this.id
  data_collection_rule_id = azurerm_monitor_data_collection_rule.prometheus.id
}

# ------------------------------------------------------------
# Control plane metrics
# ------------------------------------------------------------
# azurerm has no argument for this yet, so set it via azapi. It is applied
# after the DCR association exists so the control plane collector starts with
# its destination already wired up (same ordering the Azure CLI uses).
# Equivalent CLI: az aks update -g <rg> -n <aks> --enable-control-plane-metrics
resource "azapi_update_resource" "control_plane_metrics" {
  count = var.enable_control_plane_metrics ? 1 : 0

  type        = "Microsoft.ContainerService/managedClusters@2026-04-01"
  resource_id = azurerm_kubernetes_cluster.this.id

  body = {
    properties = {
      azureMonitorProfile = {
        metrics = {
          enabled = true
          controlPlane = {
            enabled = true
          }
        }
      }
    }
  }

  depends_on = [azurerm_monitor_data_collection_rule_association.prometheus]
}

# ------------------------------------------------------------
# Azure Managed Grafana
# ------------------------------------------------------------
resource "azurerm_dashboard_grafana" "this" {
  name                  = local.grafana_name
  resource_group_name   = azurerm_resource_group.this.name
  location              = azurerm_resource_group.this.location
  grafana_major_version = var.grafana_major_version
  tags                  = local.tags

  identity {
    type = "SystemAssigned"
  }

  azure_monitor_workspace_integrations {
    resource_id = azurerm_monitor_workspace.this.id
  }
}

# Grafana reads metrics from the Azure Monitor workspace.
resource "azurerm_role_assignment" "grafana_monitoring_data_reader" {
  scope                = azurerm_monitor_workspace.this.id
  role_definition_name = "Monitoring Data Reader"
  principal_id         = azurerm_dashboard_grafana.this.identity[0].principal_id
}

# Grant the deploying user Grafana Admin so they can import dashboards.
resource "azurerm_role_assignment" "grafana_admin" {
  count                = var.user_object_id != "" ? 1 : 0
  scope                = azurerm_dashboard_grafana.this.id
  role_definition_name = "Grafana Admin"
  principal_id         = var.user_object_id
}
