resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

resource "azurerm_log_analytics_workspace" "main" {
  name                = "law-${var.cluster_name}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  tags                = var.tags
}

# Custom, readable node resource group name instead of the AKS-generated MC_* default.
locals {
  node_resource_group = "rg-${var.cluster_name}-nodes"
}

resource "azurerm_kubernetes_cluster" "main" {
  name                = var.cluster_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  dns_prefix          = var.cluster_name
  kubernetes_version  = var.kubernetes_version
  node_resource_group = local.node_resource_group
  sku_tier            = "Standard"

  # Node auto-provisioning (NAP) requires this block. NAP manages Karpenter NodePools/AKSNodeClasses
  # to provision right-sized nodes for pending pods on top of the required system node pool below.
  node_provisioning_profile {
    mode               = "Auto"
    default_node_pools = var.node_provisioning_default_pools
  }

  # NAP requires Azure CNI Overlay + Cilium dataplane and a Standard Load Balancer.
  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_data_plane  = "cilium"
    network_policy      = "cilium"
    load_balancer_sku   = "standard"
  }

  # Required system node pool. Keep it small and critical-addons-only; NAP provisions the
  # workload-facing capacity dynamically via NodePool/AKSNodeClass manifests.
  default_node_pool {
    name                         = "system"
    vm_size                      = var.system_node_vm_size
    node_count                   = var.system_node_count
    only_critical_addons_enabled = true
  }

  identity {
    type = "SystemAssigned"
  }

  oms_agent {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  }

  tags = var.tags
}

# Surface NAP/Karpenter control plane activity (category "node-auto-provisioning") in Log Analytics
# so the "AKSControlPlane | where Category == 'karpenter-events'" sample query works out of the box.
resource "azurerm_monitor_diagnostic_setting" "nap" {
  name                       = "diag-node-auto-provisioning"
  target_resource_id         = azurerm_kubernetes_cluster.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  enabled_log {
    category = "node-auto-provisioning"
  }
}

resource "azurerm_role_assignment" "user_cluster_admin" {
  count                = var.user_object_id != "" ? 1 : 0
  scope                = azurerm_kubernetes_cluster.main.id
  role_definition_name = "Azure Kubernetes Service RBAC Cluster Admin"
  principal_id         = var.user_object_id
}
