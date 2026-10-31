locals {
  name_prefix = "${var.project}-${var.environment}"
  tags = {
    project     = var.project
    environment = var.environment
    managed_by  = "terraform"
    demo        = "aks-flux-extension"
  }
}

resource "azurerm_resource_group" "this" {
  name     = "rg-${local.name_prefix}"
  location = var.location
  tags     = local.tags
}

resource "azurerm_kubernetes_cluster" "this" {
  name                = "aks-${local.name_prefix}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  node_resource_group = "rg-${local.name_prefix}-nodes"
  dns_prefix          = "aks-${local.name_prefix}"
  kubernetes_version  = var.kubernetes_version
  sku_tier            = "Free"

  default_node_pool {
    name       = "system"
    node_count = var.node_count
    vm_size    = var.node_vm_size
    os_sku     = "AzureLinux"

    upgrade_settings {
      max_surge = "33%"
    }
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_data_plane  = "cilium"
    network_policy      = "cilium"
    load_balancer_sku   = "standard"
  }

  role_based_access_control_enabled = true
  tags                              = local.tags
}

resource "azurerm_kubernetes_cluster_extension" "flux" {
  name              = "flux"
  cluster_id        = azurerm_kubernetes_cluster.this.id
  extension_type    = "microsoft.flux"
  release_train     = "Stable"
  release_namespace = "flux-system"
}

resource "azurerm_kubernetes_flux_configuration" "this" {
  name                              = "cluster-config"
  cluster_id                        = azurerm_kubernetes_cluster.this.id
  namespace                         = "cluster-config"
  scope                             = "cluster"
  continuous_reconciliation_enabled = true

  git_repository {
    url                      = var.git_repository_url
    reference_type           = "branch"
    reference_value          = var.git_branch
    sync_interval_in_seconds = 60
    timeout_in_seconds       = 120
  }

  kustomizations {
    name                       = "apps"
    path                       = var.gitops_path
    garbage_collection_enabled = true
    sync_interval_in_seconds   = 60
    retry_interval_in_seconds  = 30
    timeout_in_seconds         = 300
  }

  depends_on = [azurerm_kubernetes_cluster_extension.flux]
}