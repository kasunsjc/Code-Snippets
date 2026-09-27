locals {
  name_prefix         = "${var.project}-${var.environment}"
  resource_group_name = "rg-${local.name_prefix}"
  node_resource_group = "rg-${local.name_prefix}-nodes"
  cluster_name        = "aks-${local.name_prefix}"
  log_workspace_name  = "log-${local.name_prefix}"
  prometheus_ws_name  = "prom-${local.name_prefix}"
  # Azure Managed Grafana names are capped at 23 chars, letters/digits/dashes only.
  grafana_name  = "graf-${substr(replace(local.name_prefix, "-", ""), 0, 12)}-${random_string.suffix.result}"
  bookinfo_fqdn = "${var.bookinfo_subdomain}.${var.dns_zone_name}"

  tags = merge({
    project     = var.project
    environment = var.environment
    demo        = "aks-istio-service-mesh"
    managed_by  = "terraform"
  }, var.tags)
}

data "azurerm_client_config" "current" {}

# service_mesh_profile.revisions requires >= 1 entry (the provider docs'
# "leave it empty" claim doesn't hold in practice) - resolve AKS's current
# default supported revision for this region/Kubernetes version when the
# caller didn't pin one.
data "external" "istio_default_revision" {
  count   = length(var.istio_revisions) == 0 ? 1 : 0
  program = ["bash", "${path.module}/scripts/default-istio-revision.sh", var.location, var.kubernetes_version]
}

locals {
  istio_revisions = length(var.istio_revisions) > 0 ? var.istio_revisions : [data.external.istio_default_revision[0].result.revision]
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

# --- Existing Azure DNS zone (not created here; must already be delegated) ----

data "azurerm_dns_zone" "this" {
  name                = var.dns_zone_name
  resource_group_name = var.dns_zone_resource_group
}

# --- Workload identity for cert-manager's Azure DNS DNS-01 solver -------------
# No client secret: cert-manager exchanges its Kubernetes service account token
# for an Azure AD token via the cluster's OIDC issuer (Azure Workload Identity).

resource "azurerm_user_assigned_identity" "cert_manager" {
  name                = "id-cert-manager-${local.name_prefix}"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  tags                = local.tags
}

resource "azurerm_federated_identity_credential" "cert_manager" {
  name                      = "cert-manager"
  user_assigned_identity_id = azurerm_user_assigned_identity.cert_manager.id
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = azurerm_kubernetes_cluster.this.oidc_issuer_url
  subject                   = "system:serviceaccount:cert-manager:cert-manager"
}

# Scoped to the single DNS zone only - not subscription- or RG-wide access.
resource "azurerm_role_assignment" "cert_manager_dns_zone_contributor" {
  scope                = data.azurerm_dns_zone.this.id
  role_definition_name = "DNS Zone Contributor"
  principal_id         = azurerm_user_assigned_identity.cert_manager.principal_id
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
  grafana_major_version         = "12"
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

  # Required for cert-manager's Azure Workload Identity federated credential.
  oidc_issuer_enabled       = true
  workload_identity_enabled = true

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
    revisions                        = local.istio_revisions
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
