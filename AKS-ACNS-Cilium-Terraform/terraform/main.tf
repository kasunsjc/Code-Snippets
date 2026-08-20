# ============================================================
# AKS with Advanced Container Networking Services (ACNS)
# ------------------------------------------------------------
# - Azure CNI overlay + Cilium data plane
# - ACNS: Container Network Observability + Network Security
# - Azure Managed Prometheus (Azure Monitor workspace + DCR)
# - Azure Managed Grafana with prebuilt networking dashboards
# ============================================================

locals {
  node_resource_group_name = "rg-${var.cluster_name}-nodes"
  grafana_name             = substr("${var.cluster_name}-graf", 0, 23)
}

resource "azurerm_resource_group" "this" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

# ------------------------------------------------------------
# Azure Monitor workspace (Managed Prometheus)
# ------------------------------------------------------------
resource "azurerm_monitor_workspace" "this" {
  name                = "${var.cluster_name}-amw"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  tags                = var.tags
}

# ------------------------------------------------------------
# AKS cluster with Cilium data plane + ACNS
# ------------------------------------------------------------
resource "azurerm_kubernetes_cluster" "this" {
  name                = var.cluster_name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  dns_prefix          = var.cluster_name
  kubernetes_version  = var.kubernetes_version
  node_resource_group = local.node_resource_group_name
  tags                = var.tags

  default_node_pool {
    name                 = "system"
    vm_size              = var.node_vm_size
    node_count           = var.node_count
    auto_scaling_enabled = true
    min_count            = var.node_min_count
    max_count            = var.node_max_count
    zones                = ["1", "2", "3"]

    upgrade_settings {
      max_surge = "10%"
    }
  }

  identity {
    type = "SystemAssigned"
  }

  # Required for Managed Prometheus metrics collection
  monitor_metrics {}

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_data_plane  = "cilium"
    network_policy      = "cilium"
    pod_cidr            = var.pod_cidr

    # Advanced Container Networking Services
    advanced_networking {
      observability_enabled = true
      security_enabled      = true
    }
  }

  lifecycle {
    ignore_changes = [default_node_pool[0].node_count]
  }
}

# ------------------------------------------------------------
# Managed Prometheus data collection (DCE + DCR + association)
# ------------------------------------------------------------
resource "azurerm_monitor_data_collection_endpoint" "prometheus" {
  name                = "MSProm-${var.cluster_name}"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  kind                = "Linux"
  tags                = var.tags
}

resource "azurerm_monitor_data_collection_rule" "prometheus" {
  name                        = "MSProm-${var.cluster_name}"
  resource_group_name         = azurerm_resource_group.this.name
  location                    = azurerm_resource_group.this.location
  data_collection_endpoint_id = azurerm_monitor_data_collection_endpoint.prometheus.id
  kind                        = "Linux"
  tags                        = var.tags

  data_sources {
    prometheus_forwarder {
      name    = "PrometheusDataSource"
      streams = ["Microsoft-PrometheusMetrics"]
    }
  }

  destinations {
    monitor_account {
      name               = "MonitoringAccount"
      monitor_account_id = azurerm_monitor_workspace.this.id
    }
  }

  data_flow {
    streams      = ["Microsoft-PrometheusMetrics"]
    destinations = ["MonitoringAccount"]
  }
}

resource "azurerm_monitor_data_collection_rule_association" "prometheus" {
  name                    = "MSProm-${var.cluster_name}"
  target_resource_id      = azurerm_kubernetes_cluster.this.id
  data_collection_rule_id = azurerm_monitor_data_collection_rule.prometheus.id
}

# ------------------------------------------------------------
# Azure Managed Grafana
# ------------------------------------------------------------
resource "azurerm_dashboard_grafana" "this" {
  name                  = local.grafana_name
  resource_group_name   = azurerm_resource_group.this.name
  location              = azurerm_resource_group.this.location
  grafana_major_version = 11
  tags                  = var.tags

  identity {
    type = "SystemAssigned"
  }

  azure_monitor_workspace_integrations {
    resource_id = azurerm_monitor_workspace.this.id
  }
}

# Grafana reads metrics from the Azure Monitor workspace
resource "azurerm_role_assignment" "grafana_monitoring_reader" {
  scope                = azurerm_monitor_workspace.this.id
  role_definition_name = "Monitoring Data Reader"
  principal_id         = azurerm_dashboard_grafana.this.identity[0].principal_id
}

# Grant the deploying user Grafana Admin (optional)
resource "azurerm_role_assignment" "grafana_admin" {
  count                = var.user_object_id != "" ? 1 : 0
  scope                = azurerm_dashboard_grafana.this.id
  role_definition_name = "Grafana Admin"
  principal_id         = var.user_object_id
}
