locals {
  name_prefix         = "${var.project}-${var.environment}"
  resource_group_name = "rg-${local.name_prefix}"
  cluster_name        = "aks-${local.name_prefix}"
  node_resource_group = "rg-${local.cluster_name}-nodes"
  log_workspace_name  = "log-${local.name_prefix}"
  monitor_ws_name     = "amw-${local.name_prefix}"
  grafana_name        = "grafana-${local.name_prefix}"
  harbor_fqdn         = "${var.harbor_subdomain}.${var.dns_zone_name}"

  tags = merge(var.tags, {
    environment = var.environment
  })
}

data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "this" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.tags
}

# --- Existing DNS zone (not created here; must already be delegated) ---------

data "azurerm_dns_zone" "this" {
  name                = var.dns_zone_name
  resource_group_name = var.dns_zone_resource_group
}

data "azurerm_resource_group" "dns_zone" {
  name = var.dns_zone_resource_group
}

# --- Observability: Container Insights (audit-log blog) -----------------------

resource "azurerm_log_analytics_workspace" "this" {
  name                = local.log_workspace_name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = local.tags
}

# --- Observability: Managed Prometheus + Grafana (metrics blog) --------------

resource "azurerm_monitor_workspace" "this" {
  name                = local.monitor_ws_name
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  tags                = local.tags
}

resource "azurerm_monitor_data_collection_endpoint" "prometheus" {
  name                = "MSProm-${local.cluster_name}"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  kind                = "Linux"
  tags                = local.tags
}

resource "azurerm_monitor_data_collection_rule" "prometheus" {
  name                        = "MSProm-${local.cluster_name}"
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
  name                    = "MSProm-${local.cluster_name}"
  target_resource_id      = azurerm_kubernetes_cluster.this.id
  data_collection_rule_id = azurerm_monitor_data_collection_rule.prometheus.id
}

resource "azurerm_dashboard_grafana" "this" {
  name                  = local.grafana_name
  resource_group_name   = azurerm_resource_group.this.name
  location              = azurerm_resource_group.this.location
  grafana_major_version = 12
  tags                  = local.tags

  identity {
    type = "SystemAssigned"
  }

  azure_monitor_workspace_integrations {
    resource_id = azurerm_monitor_workspace.this.id
  }
}

resource "azurerm_role_assignment" "grafana_monitoring_reader" {
  scope                = azurerm_monitor_workspace.this.id
  role_definition_name = "Monitoring Data Reader"
  principal_id         = azurerm_dashboard_grafana.this.identity[0].principal_id
}

resource "azurerm_role_assignment" "grafana_admin_user" {
  count                = var.user_object_id == "" ? 0 : 1
  scope                = azurerm_dashboard_grafana.this.id
  role_definition_name = "Grafana Admin"
  principal_id         = var.user_object_id
}

# --- Workload identity for cert-manager's Azure DNS DNS-01 solver -------------

resource "azurerm_user_assigned_identity" "cert_manager" {
  name                = "id-cert-manager-${local.name_prefix}"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  tags                = local.tags
}

resource "azurerm_federated_identity_credential" "cert_manager" {
  name                = "cert-manager"
  resource_group_name = azurerm_resource_group.this.name
  parent_id           = azurerm_user_assigned_identity.cert_manager.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = azurerm_kubernetes_cluster.this.oidc_issuer_url
  subject             = "system:serviceaccount:cert-manager:cert-manager"
}

resource "azurerm_role_assignment" "cert_manager_dns_zone_contributor" {
  scope                = data.azurerm_dns_zone.this.id
  role_definition_name = "DNS Zone Contributor"
  principal_id         = azurerm_user_assigned_identity.cert_manager.principal_id
}

# cert-manager's Azure DNS solver lists zones at the resource group scope before
# reading the specific zone; Reader here avoids a 403 during propagation checks
# (same gotcha documented for external-dns in AKS-ArgoCD-Extension).
resource "azurerm_role_assignment" "cert_manager_dns_rg_reader" {
  scope                = data.azurerm_resource_group.dns_zone.id
  role_definition_name = "Reader"
  principal_id         = azurerm_user_assigned_identity.cert_manager.principal_id
}

# --- AKS cluster ---------------------------------------------------------------

resource "azurerm_kubernetes_cluster" "this" {
  name                = local.cluster_name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  dns_prefix          = local.cluster_name
  kubernetes_version  = var.kubernetes_version
  node_resource_group = local.node_resource_group
  tags                = local.tags

  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  default_node_pool {
    name                 = "system"
    vm_size              = var.node_vm_size
    node_count           = var.node_count
    auto_scaling_enabled = true
    min_count            = var.node_min_count
    max_count            = var.node_max_count
    upgrade_settings {
      max_surge = "10%"
    }
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
  }

  oms_agent {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id
  }

  monitor_metrics {}
}

# --- Harbor admin password (generated, never committed) -----------------------

resource "random_password" "harbor_admin" {
  length  = 20
  special = true
}
